import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import 'road_reliability.dart';

class GeminiSafetyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent';

  Future<void> analyzePlace(String placeId) async {
    print('[GEMINI DEBUG] === analyzePlace START ===');
    print('[GEMINI DEBUG] placeId: "$placeId"');

    try {
      // STEP 4-5: Read reviews from Firestore
      print('[GEMINI DEBUG] Step 4: Reading reviews from places/$placeId/reviews');
      final reviewsSnap = await _db
          .collection('places')
          .doc(placeId)
          .collection('reviews')
          .get();

      print('[GEMINI DEBUG] Step 5: Reviews retrieved: ${reviewsSnap.docs.length}');

      if (reviewsSnap.docs.isEmpty) {
        print('[GEMINI DEBUG] ABORT: No reviews found for placeId "$placeId"');
        return;
      }

      // Print each review's raw data for debugging
      for (var i = 0; i < reviewsSnap.docs.length; i++) {
        final doc = reviewsSnap.docs[i];
        print('[GEMINI DEBUG] Review $i: id=${doc.id}, data=${doc.data()}');
      }

      final reviewsJson = reviewsSnap.docs.map((doc) {
        final d = doc.data();
        return {
          'overallSafety': d['overallSafety'],
          'timeOfDay': d['timeOfDay'],
          'lighting': d['lighting'],
          'crowd': d['crowd'],
          'policePresence': d['policePresence'],
          'walkAlone': d['walkingAlone'],
          'comment': d['comment'] ?? '',
        };
      }).toList();

      // STEP 6: Print the prompt
      final prompt = _buildPrompt(reviewsJson);
      print('[GEMINI DEBUG] Step 6: Prompt sent to Gemini:');
      print('[GEMINI DEBUG] --- PROMPT START ---');
      print(prompt);
      print('[GEMINI DEBUG] --- PROMPT END ---');

      // STEP 7-8: Call Gemini API
      print('[GEMINI DEBUG] Step 7: Calling Gemini API...');
      final result = await _callGemini(prompt, reviews: reviewsJson);
      print('[GEMINI DEBUG] Step 8: Gemini returned: $result');

      if (result == null) {
        print('[GEMINI DEBUG] ABORT: _callGemini returned null');
        return;
      }

      // STEP 9-10: Verify parsed values
      print('[GEMINI DEBUG] Step 9-10: Parsed score=${result['score']}, summary="${result['summary']}"');

      // STEP 11-12: Update Firestore
      print('[GEMINI DEBUG] Step 11: Updating Firestore places/$placeId');
      await _db.collection('places').doc(placeId).update({
        'score': result['score'],
        'summary': result['summary'],
        'lastAnalyzedAt': FieldValue.serverTimestamp(),
        'reviewCount': reviewsSnap.docs.length,
      });
      print('[GEMINI DEBUG] Step 12: Firestore update SUCCESS');
      print('[GEMINI DEBUG] === analyzePlace END (SUCCESS) ===');
    } catch (e, stackTrace) {
      print('[GEMINI DEBUG] === ERROR in analyzePlace ===');
      print('[GEMINI DEBUG] Error: $e');
      print('[GEMINI DEBUG] StackTrace: $stackTrace');
    }
  }

  Future<void> analyzeRoad(String roadZoneId) async {
    try {
      final reviewsSnap = await _db
          .collection('road_zones')
          .doc(roadZoneId)
          .collection('reviews')
          .get();

      if (reviewsSnap.docs.isEmpty) return;

      final reviewsJson = reviewsSnap.docs.map((doc) {
        final d = doc.data();
        return {
          'overallSafety': d['overallSafety'],
          'timeOfDay': d['timeOfDay'],
          'lighting': d['lighting'],
          'crowd': d['crowd'],
          'policePresence': d['policePresence'],
          'walkAlone': d['walkingAlone'],
          'comment': d['comment'] ?? '',
        };
      }).toList();

      // Calculate reliability locally from review evidence
      final safetyRatings = reviewsSnap.docs
          .map((doc) => (doc.data()['overallSafety'] as int?) ?? 3)
          .toList();
      final reliability = RoadReliability.calculate(
        reviewCount: reviewsSnap.docs.length,
        safetyRatings: safetyRatings,
      );

      final prompt = _buildPrompt(reviewsJson);
      final result = await _callGemini(prompt, reviews: reviewsJson);

      if (result == null) return;

      await _db.collection('road_zones').doc(roadZoneId).update({
        'aiScore': result['score'],
        'aiSummary': result['summary'],
        'reliability': reliability,
        'lastAnalyzedAt': FieldValue.serverTimestamp(),
        'reviewCount': reviewsSnap.docs.length,
      });
    } catch (_) {}
  }

  String _buildPrompt(List<Map<String, dynamic>> reviews) {
    final reviewsStr = const JsonEncoder.withIndent('  ').convert(reviews);

    return '''You are a safety analyst for women in India. Score this location's safety for a woman walking alone, based ONLY on the community reviews below.

SCORING RUBRIC (use the FULL 0-100 range):

90-100: VERY SAFE
- Excellent lighting, busy area, frequent police patrols
- Multiple reviews saying "feel safe", "well-lit", "safe at night"
- No negative reports

75-89: SAFE
- Good lighting, decent foot traffic
- Generally positive reviews
- Minor concerns mentioned but overall positive

60-74: MODERATELY SAFE
- Adequate conditions but some concerns
- Mixed reviews — some positive, some cautionary
- Lighting or crowd could be better

40-59: USE CAUTION
- Notable safety concerns mentioned
- Poor lighting, isolated, or infrequent patrols
- Reviews express some discomfort

20-39: UNSAFE
- Multiple negative reviews
- Reports of harassment, poor lighting, isolated
- Reviews recommend avoiding or being very careful

0-19: VERY UNSAFE
- Strong evidence of danger
- Reviews describe threats, attacks, or extreme isolation
- Consensus that the area is dangerous

IMPORTANT RULES:
- A place with ALL positive reviews (5 stars, good lighting, busy, police present) should score 85-95
- A place with mixed reviews should score 40-70 depending on the balance
- A place with mostly negative reviews should score 10-35
- DO NOT cluster everything around 30-50. Use the full range.
- Be decisive: differentiate between genuinely safe and genuinely unsafe places

Return ONLY valid JSON:
{"score": <0-100 integer>, "summary": "<one line safety summary>"}

Reviews:
$reviewsStr''';
  }

  Future<Map<String, dynamic>?> _callGemini(String prompt, {List<Map<String, dynamic>>? reviews}) async {
    final apiKey = ApiKeys.gemini;
    print('[GEMINI DEBUG] API key length: ${apiKey.length}, starts with: "${apiKey.substring(0, apiKey.length > 10 ? 10 : apiKey.length)}..."');

    if (apiKey.isEmpty) {
      print('[GEMINI DEBUG] ABORT: API key is empty');
      return null;
    }

    final url = Uri.parse('$_baseUrl?key=$apiKey');
    print('[GEMINI DEBUG] URL: $url');

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 256,
          'thinkingConfig': {'thinkingBudget': 0},
        },
    });

    print('[GEMINI DEBUG] Request body length: ${requestBody.length} chars');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    );

    print('[GEMINI DEBUG] Response status: ${response.statusCode}');
    print('[GEMINI DEBUG] Response body: ${response.body}');

    if (response.statusCode != 200) {
      print('[GEMINI DEBUG] ABORT: Non-200 status code ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      print('[GEMINI DEBUG] ABORT: No candidates in response');
      return null;
    }

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      print('[GEMINI DEBUG] ABORT: No parts in response');
      return null;
    }

    final text = parts[0]['text'] as String?;
    if (text == null) {
      print('[GEMINI DEBUG] ABORT: No text in response');
      return null;
    }

    print('[GEMINI DEBUG] Raw Gemini text: $text');

    return _parseResponse(text, reviews: reviews);
  }

  Map<String, dynamic>? _parseResponse(String text, {List<Map<String, dynamic>>? reviews}) {
    try {
      final cleaned = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      print('[GEMINI DEBUG] Cleaned response: $cleaned');

      final decoded = jsonDecode(cleaned);

      Map<String, dynamic> parsed;
      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      } else if (decoded is List && decoded.isNotEmpty) {
        parsed = decoded.first as Map<String, dynamic>;
      } else {
        print('[GEMINI DEBUG] ABORT: Unexpected response type: ${decoded.runtimeType}');
        return null;
      }

      final score = parsed['score'];
      final summary = parsed['summary'];

      print('[GEMINI DEBUG] Parsed score type: ${score.runtimeType}, value: $score');
      print('[GEMINI DEBUG] Parsed summary type: ${summary.runtimeType}, value: $summary');

      if (score is! num || summary is! String) {
        print('[GEMINI DEBUG] ABORT: Type check failed. score is num: ${score is num}, summary is String: ${summary is String}');
        return null;
      }

      var finalScore = score.toInt().clamp(0, 100);

      // Normalization: if Gemini returned a compressed score but reviews
      // suggest a different range, blend toward the review baseline.
      if (reviews != null && reviews.isNotEmpty) {
        finalScore = _normalizeScore(finalScore, reviews);
      }

      final result = {
        'score': finalScore,
        'summary': summary.length > 300 ? summary.substring(0, 300) : summary,
      };
      print('[GEMINI DEBUG] Final parsed result: $result');
      return result;
    } catch (e) {
      print('[GEMINI DEBUG] JSON parse error: $e');
      return null;
    }
  }

  /// Normalizes Gemini score using review data as anchor.
  /// If Gemini compresses scores (e.g., returns 35 for a great place),
  /// this pulls the score toward what the reviews actually indicate.
  int _normalizeScore(int geminiScore, List<Map<String, dynamic>> reviews) {
    final ratings = reviews
        .map((r) => (r['overallSafety'] as num?)?.toDouble() ?? 3.0)
        .toList();
    if (ratings.isEmpty) return geminiScore;

    final avg = ratings.reduce((a, b) => a + b) / ratings.length;

    // Map average 1-5 rating to 0-100 baseline
    final baseline = ((avg - 1) / 4 * 100).round().clamp(0, 100);

    // If Gemini score is far from the review baseline, blend 50/50
    final diff = (geminiScore - baseline).abs();
    if (diff > 20) {
      final blended = ((geminiScore + baseline) / 2).round();
      print('[GEMINI DEBUG] Normalized: gemini=$geminiScore, baseline=$baseline, blended=$blended');
      return blended.clamp(0, 100);
    }

    return geminiScore;
  }
}
