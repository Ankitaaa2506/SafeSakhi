import 'dart:math';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createUser(AppUser user) async {
    await _db.collection('users').doc(user.uid).set(user.toFirestore());
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> upsertUser(AppUser user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      await createUser(user);
    } else {
      await updateUser(user.uid, {
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoUrl,
      });
    }
  }

  Future<void> addPlaceReview(String placeId, Map<String, dynamic> data) async {
    final placeRef = _db.collection('places').doc(placeId);
    final reviewsRef = placeRef.collection('reviews');

    await _db.runTransaction((tx) async {
      final placeSnap = await tx.get(placeRef);
      if (!placeSnap.exists) {
        tx.set(placeRef, {
          'id': placeId,
          'createdAt': FieldValue.serverTimestamp(),
          'reviewCount': 1,
        });
      } else {
        tx.update(placeRef, {'reviewCount': FieldValue.increment(1)});
      }

      final docRef = reviewsRef.doc();
      tx.set(docRef, {
        ...data,
        'id': docRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Dual-write to user's subcollection for profile/review queries
      final userId = data['userId'] as String?;
      if (userId != null && userId != 'anonymous') {
        final userReviewRef = _db.collection('users').doc(userId)
            .collection('userReviews').doc(docRef.id);
        tx.set(userReviewRef, {
          ...data,
          'id': docRef.id,
          'placeId': placeId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        developer.log('Dual-write: users/$userId/userReviews/${docRef.id}', name: 'FirestoreService');
      } else {
        developer.log('SKIP dual-write: userId=$userId (anonymous or null)', name: 'FirestoreService');
      }
    });
  }

  Future<void> addRoadReview(String zoneId, Map<String, dynamic> data) async {
    final zoneRef = _db.collection('road_zones').doc(zoneId);
    final reviewsRef = zoneRef.collection('reviews');

    await _db.runTransaction((tx) async {
      final zoneSnap = await tx.get(zoneRef);
      if (!zoneSnap.exists) {
        tx.set(zoneRef, {
          'id': zoneId,
          'roadName': data['roadName'] ?? 'Road Segment',
          'roadClass': data['roadClass'],
          'centerLatitude': data['latitude'],
          'centerLongitude': data['longitude'],
          'radiusMeters': 50,
          'createdAt': FieldValue.serverTimestamp(),
          'reviewCount': 1,
          'aiScore': null,
          'aiSummary': null,
          'reliability': 0.0,
          'lastAnalyzedAt': null,
        });
      } else {
        tx.update(zoneRef, {'reviewCount': FieldValue.increment(1)});
      }

      final docRef = reviewsRef.doc();
      tx.set(docRef, {
        ...data,
        'id': docRef.id,
        'roadZoneId': zoneId,
        'reviewType': 'road',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Dual-write to user's subcollection for profile/review queries
      final userId = data['userId'] as String?;
      if (userId != null && userId != 'anonymous') {
        final userReviewRef = _db.collection('users').doc(userId)
            .collection('userReviews').doc(docRef.id);
        tx.set(userReviewRef, {
          ...data,
          'id': docRef.id,
          'roadZoneId': zoneId,
          'reviewType': 'road',
          'createdAt': FieldValue.serverTimestamp(),
        });
        developer.log('Dual-write (road): users/$userId/userReviews/${docRef.id}', name: 'FirestoreService');
      } else {
        developer.log('SKIP dual-write (road): userId=$userId (anonymous or null)', name: 'FirestoreService');
      }
    });
  }

  Future<QuerySnapshot> fetchPlaceReviews(String placeId, {int limit = 20, DocumentSnapshot? lastDoc}) async {
    Query query = _db
        .collection('places')
        .doc(placeId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.get();
  }

  Future<QuerySnapshot> fetchRoadReviews(String zoneId, {int limit = 20, DocumentSnapshot? lastDoc}) async {
    Query query = _db
        .collection('road_zones')
        .doc(zoneId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.get();
  }

  Stream<QuerySnapshot> streamPlaceReviews(String placeId, {int limit = 20, DocumentSnapshot? lastDoc}) {
    Query query = _db
        .collection('places')
        .doc(placeId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot> streamRoadReviews(String zoneId, {int limit = 20, DocumentSnapshot? lastDoc}) {
    Query query = _db
        .collection('road_zones')
        .doc(zoneId)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.snapshots();
  }

  Stream<DocumentSnapshot> streamPlaceDoc(String placeId) {
    return _db.collection('places').doc(placeId).snapshots();
  }

  Future<DocumentSnapshot> getPlaceDoc(String placeId) {
    return _db.collection('places').doc(placeId).get();
  }

  Stream<DocumentSnapshot> streamRoadZoneDoc(String zoneId) {
    return _db.collection('road_zones').doc(zoneId).snapshots();
  }

  Future<DocumentSnapshot> getRoadZoneDoc(String zoneId) {
    return _db.collection('road_zones').doc(zoneId).get();
  }

  static String resolveRoadZoneId(String? roadName, double lat, double lng) {
    if (roadName != null && roadName.trim().isNotEmpty) {
      final slug = roadName
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+\$'), '');
      return 'road_$slug';
    }
    return 'road_${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
  }

  /// Resolve or create a road safety zone within 50m radius.
  ///
  /// 1. Query road_zones for same road name.
  /// 2. Compute distance from tap to each zone center.
  /// 3. If any zone is within 50m → return nearest.
  /// 4. Otherwise → create new zone.
  Future<String> resolveNearestRoadZone({
    required String? roadName,
    required double latitude,
    required double longitude,
    String? roadClass,
  }) async {
    const radiusMeters = 50.0;

    // Query zones with the same road name
    Query query = _db.collection('road_zones');
    if (roadName != null && roadName.trim().isNotEmpty) {
      query = query.where('roadName', isEqualTo: roadName);
    }

    final snap = await query.get();

    // Find nearest zone within radius
    String? nearestZoneId;
    double nearestDist = double.infinity;

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final clat = data?['centerLatitude'] as double?;
      final clng = data?['centerLongitude'] as double?;
      if (clat == null || clng == null) continue;

      final dist = _haversineMeters(latitude, longitude, clat, clng);
      if (dist < radiusMeters && dist < nearestDist) {
        nearestDist = dist;
        nearestZoneId = doc.id;
      }
    }

    if (nearestZoneId != null) {
      return nearestZoneId;
    }

    // No existing zone within radius — create new one
    final zoneId = resolveRoadZoneId(roadName, latitude, longitude);
    await _db.collection('road_zones').doc(zoneId).set({
      'id': zoneId,
      'roadName': roadName ?? 'Road Segment',
      'roadClass': roadClass,
      'centerLatitude': latitude,
      'centerLongitude': longitude,
      'radiusMeters': radiusMeters,
      'createdAt': FieldValue.serverTimestamp(),
      'reviewCount': 0,
      'aiScore': null,
      'aiSummary': null,
      'reliability': 0.0,
      'lastAnalyzedAt': null,
    });

    return zoneId;
  }

  /// Haversine distance in meters between two lat/lng points.
  static double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _deg2rad(double deg) => deg * pi / 180.0;

  /// Fetch all place reviews within [radiusMeters] of the given coordinates.
  ///
  /// Queries all places in Firestore, checks if their reviews contain
  /// latitude/longitude fields within the radius, and returns matching reviews.
  /// Returns up to [limit] reviews.
  Future<List<Map<String, dynamic>>> fetchNearbyReviews(
    double lat,
    double lng, {
    double radiusMeters = 1000,
    int limit = 50,
  }) async {
    final results = <Map<String, dynamic>>[];

    debugPrint('[SAFETY_DIAG] ═══════════════════════════════════════════');
    debugPrint('[SAFETY_DIAG] fetchNearbyReviews START');
    debugPrint('[SAFETY_DIAG] ───────────────────────────────────────────');

    debugPrint('[SAFETY_DIAG] [1] USER LOCATION');
    debugPrint('[SAFETY_DIAG]     Latitude:  $lat');
    debugPrint('[SAFETY_DIAG]     Longitude: $lng');

    debugPrint('[SAFETY_DIAG] [8] RADIUS: ${radiusMeters}m');
    debugPrint('[SAFETY_DIAG] [9] UNITS: meters');

    debugPrint('[SAFETY_DIAG] [2] COLLECTION PATH: places/{placeId}/reviews');

    try {
      final placesSnap = await _db.collection('places').get();
      debugPrint('[SAFETY_DIAG] [3] QUERY: _db.collection("places").get() → ${placesSnap.docs.length} place documents');
      debugPrint('[SAFETY_DIAG] [4] TOTAL DOCUMENTS in "places" collection: ${placesSnap.docs.length}');

      if (placesSnap.docs.isEmpty) {
        debugPrint('[SAFETY_DIAG] [5] TOTAL REVIEWS BEFORE FILTERS: 0');
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Zero place documents exist in Firestore.');
        debugPrint('[SAFETY_DIAG] fetchNearbyReviews END — 0 results');
        debugPrint('[SAFETY_DIAG] ═══════════════════════════════════════════');
        return results;
      }

      int totalReviewsScanned = 0;
      int reviewsWithLatKey = 0;
      int reviewsWithLngKey = 0;
      int reviewsWithBothCoords = 0;
      int reviewsParseable = 0;
      int reviewsWithinRadius = 0;
      int reviewsSkippedNoLat = 0;
      int reviewsSkippedNoLng = 0;
      int reviewsSkippedUnparseable = 0;

      for (final placeDoc in placesSnap.docs) {
        final placeId = placeDoc.id;
        final placeData = placeDoc.data();

        debugPrint('[SAFETY_DIAG] ───────────────────────────────────────────');
        debugPrint('[SAFETY_DIAG] [3] PLACE DOCUMENT: places/$placeId');
        debugPrint('[SAFETY_DIAG]     Place doc keys: ${placeData.keys.toList()}');
        debugPrint('[SAFETY_DIAG]     Place doc data: $placeData');

        final reviewsSnap = await placeDoc.reference
            .collection('reviews')
            .limit(limit)
            .get();

        debugPrint('[SAFETY_DIAG]     Reviews subcollection: places/$placeId/reviews → ${reviewsSnap.docs.length} documents');

        for (final reviewDoc in reviewsSnap.docs) {
          totalReviewsScanned++;
          final data = reviewDoc.data();

          debugPrint('[SAFETY_DIAG] ───────────────────────────────────────────');
          debugPrint('[SAFETY_DIAG] [6] REVIEW DOCUMENT: places/$placeId/reviews/${reviewDoc.id}');
          debugPrint('[SAFETY_DIAG]     All keys: ${data.keys.toList()}');
          debugPrint('[SAFETY_DIAG]     Full data: $data');

          final hasLatKey = data.containsKey('latitude');
          final hasLngKey = data.containsKey('longitude');
          final hasGeoPoint = data.containsKey('location') || data.containsKey('coordinates') || data.containsKey('geoPoint');
          debugPrint('[SAFETY_DIAG] [10] FIELD NAME CHECK:');
          debugPrint('[SAFETY_DIAG]     Has "latitude" key: $hasLatKey');
          debugPrint('[SAFETY_DIAG]     Has "longitude" key: $hasLngKey');
          debugPrint('[SAFETY_DIAG]     Has "location"/"coordinates"/"geoPoint" keys: $hasGeoPoint');
          debugPrint('[SAFETY_DIAG]     Rating field: ${data['rating']}');
          debugPrint('[SAFETY_DIAG]     OverallSafety field: ${data['overallSafety']}');

          if (hasLatKey) reviewsWithLatKey++;
          if (hasLngKey) reviewsWithLngKey++;

          final reviewLat = data['latitude'];
          final reviewLng = data['longitude'];

          if (reviewLat == null) {
            reviewsSkippedNoLat++;
            debugPrint('[SAFETY_DIAG]     SKIP: latitude is null (or key missing)');
            continue;
          }
          if (reviewLng == null) {
            reviewsSkippedNoLng++;
            debugPrint('[SAFETY_DIAG]     SKIP: longitude is null (or key missing)');
            continue;
          }

          reviewsWithBothCoords++;

          final latDouble = (reviewLat is num) ? reviewLat.toDouble() : double.tryParse(reviewLat.toString());
          final lngDouble = (reviewLng is num) ? reviewLng.toDouble() : double.tryParse(reviewLng.toString());

          if (latDouble == null || lngDouble == null) {
            reviewsSkippedUnparseable++;
            debugPrint('[SAFETY_DIAG]     SKIP: CANNOT PARSE lat=$reviewLat (${reviewLat.runtimeType}), lng=$reviewLng (${reviewLng.runtimeType})');
            continue;
          }

          reviewsParseable++;
          final dist = _haversineMeters(lat, lng, latDouble, lngDouble);
          final passed = dist <= radiusMeters;
          if (passed) reviewsWithinRadius++;

          debugPrint('[SAFETY_DIAG] [7] DISTANCE CALCULATION:');
          debugPrint('[SAFETY_DIAG]     Review location: ($latDouble, $lngDouble)');
          debugPrint('[SAFETY_DIAG]     User location:   ($lat, $lng)');
          debugPrint('[SAFETY_DIAG]     Distance = ${dist.toStringAsFixed(1)} m');
          debugPrint('[SAFETY_DIAG]     Radius = ${radiusMeters}m');
          debugPrint('[SAFETY_DIAG]     passed = $passed (dist <= radius: ${dist.toStringAsFixed(1)} <= $radiusMeters)');

          if (passed) {
            results.add({
              ...data,
              'id': reviewDoc.id,
              'placeId': placeId,
              'distance': dist,
            });
          }

          if (results.length >= limit) break;
        }

        if (results.length >= limit) break;
      }

      debugPrint('[SAFETY_DIAG] ───────────────────────────────────────────');
      debugPrint('[SAFETY_DIAG] [5] TOTAL REVIEWS BEFORE LOCATION FILTERS: $totalReviewsScanned');

      debugPrint('[SAFETY_DIAG] ───────────────────────────────────────────');
      debugPrint('[SAFETY_DIAG] SUMMARY');
      debugPrint('[SAFETY_DIAG]   Reviews scanned: $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   With "latitude" key: $reviewsWithLatKey / $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   With "longitude" key: $reviewsWithLngKey / $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   With BOTH lat+lng: $reviewsWithBothCoords / $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   Parseable to double: $reviewsParseable / $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   Within ${radiusMeters}m radius: $reviewsWithinRadius / $totalReviewsScanned');
      debugPrint('[SAFETY_DIAG]   Results returned: ${results.length}');
      debugPrint('[SAFETY_DIAG]   Skipped (no lat key): $reviewsSkippedNoLat');
      debugPrint('[SAFETY_DIAG]   Skipped (no lng key): $reviewsSkippedNoLng');
      debugPrint('[SAFETY_DIAG]   Skipped (unparseable): $reviewsSkippedUnparseable');

      if (totalReviewsScanned == 0) {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Zero reviews exist.');
      } else if (reviewsWithLatKey == 0 && reviewsWithLngKey == 0) {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Reviews exist but NONE have latitude/longitude fields.');
      } else if (reviewsWithBothCoords == 0) {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Reviews exist with one of lat/lng but not both.');
      } else if (reviewsParseable == 0) {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Reviews have lat/lng keys but values are not numeric.');
      } else if (reviewsWithinRadius == 0) {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Reviews have valid coordinates but NONE within ${radiusMeters}m.');
      } else {
        debugPrint('[SAFETY_DIAG] DIAGNOSIS: Found $reviewsWithinRadius reviews within ${radiusMeters}m.');
      }

    } catch (e, stack) {
      debugPrint('[SAFETY_DIAG] ERROR: $e');
      debugPrint('[SAFETY_DIAG] Stack: $stack');
    }

    debugPrint('[SAFETY_DIAG] fetchNearbyReviews END — ${results.length} results');
    debugPrint('[SAFETY_DIAG] ═══════════════════════════════════════════');
    return results;
  }

  /// Calculate the average safety rating from a list of reviews.
  ///
  /// Checks for 'rating' or 'overallSafety' field (numeric 1-5).
  /// Returns null if no reviews have ratings.
  static double? calculateAverageRating(List<Map<String, dynamic>> reviews) {
    if (reviews.isEmpty) return null;

    double sum = 0;
    int count = 0;

    for (final review in reviews) {
      final rating = review['rating'] ?? review['overallSafety'];
      if (rating == null) continue;

      double ratingValue;
      if (rating is int) {
        ratingValue = rating.toDouble();
      } else if (rating is double) {
        ratingValue = rating;
      } else if (rating is num) {
        ratingValue = rating.toDouble();
      } else {
        continue;
      }

      sum += ratingValue;
      count++;
    }

    if (count == 0) return null;
    return sum / count;
  }

  Future<List<Map<String, dynamic>>> fetchUserReviews(String userId) async {
    developer.log('fetchUserReviews: querying users/$userId/userReviews', name: 'FirestoreService');

    // Query user's own subcollection — no collectionGroup index needed
    final snap = await _db
        .collection('users')
        .doc(userId)
        .collection('userReviews')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();

    developer.log('fetchUserReviews: found ${snap.docs.length} docs in userReviews', name: 'FirestoreService');

    final results = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final reviewType = data['reviewType'] as String? ?? 'place';

      final String placeName;
      if (data['roadName'] != null) {
        placeName = data['roadName'] as String;
      } else if (data['placeName'] != null) {
        placeName = data['placeName'] as String;
      } else {
        placeName = reviewType == 'road' ? 'Road Segment' : 'Place';
      }

      results.add({
        'review': data,
        'placeId': data['placeId'] ?? doc.id,
        'placeName': placeName,
        'reviewType': reviewType,
      });
    }

    developer.log('fetchUserReviews: returning ${results.length} reviews', name: 'FirestoreService');
    return results;
  }

  /// One-time migration: copies existing reviews from places/*/reviews and
  /// road_zones/*/reviews into users/{uid}/userReviews.
  /// Call this once to backfill data written before the dual-write fix.
  Future<int> migrateExistingReviews(String userId) async {
    developer.log('=== MIGRATION START for userId=$userId ===', name: 'FirestoreService');
    int migrated = 0;

    // 1. Migrate place reviews
    try {
      final placesSnap = await _db.collection('places').get();
      developer.log('Migration: found ${placesSnap.docs.length} places', name: 'FirestoreService');

      for (final placeDoc in placesSnap.docs) {
        final reviewsSnap = await placeDoc.reference
            .collection('reviews')
            .where('userId', isEqualTo: userId)
            .get();

        for (final reviewDoc in reviewsSnap.docs) {
          final data = reviewDoc.data();
          final userReviewRef = _db.collection('users').doc(userId)
              .collection('userReviews').doc(reviewDoc.id);

          // Check if already migrated
          final existing = await userReviewRef.get();
          if (existing.exists) continue;

          await userReviewRef.set({
            ...data,
            'id': reviewDoc.id,
            'placeId': placeDoc.id,
            'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          });
          migrated++;
          developer.log('Migration: place review ${reviewDoc.id} → users/$userId/userReviews', name: 'FirestoreService');
        }
      }
    } catch (e) {
      developer.log('Migration place error: $e', name: 'FirestoreService');
    }

    // 2. Migrate road reviews
    try {
      final zonesSnap = await _db.collection('road_zones').get();
      developer.log('Migration: found ${zonesSnap.docs.length} road_zones', name: 'FirestoreService');

      for (final zoneDoc in zonesSnap.docs) {
        final reviewsSnap = await zoneDoc.reference
            .collection('reviews')
            .where('userId', isEqualTo: userId)
            .get();

        for (final reviewDoc in reviewsSnap.docs) {
          final data = reviewDoc.data();
          final userReviewRef = _db.collection('users').doc(userId)
              .collection('userReviews').doc(reviewDoc.id);

          final existing = await userReviewRef.get();
          if (existing.exists) continue;

          await userReviewRef.set({
            ...data,
            'id': reviewDoc.id,
            'roadZoneId': zoneDoc.id,
            'reviewType': 'road',
            'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
          });
          migrated++;
          developer.log('Migration: road review ${reviewDoc.id} → users/$userId/userReviews', name: 'FirestoreService');
        }
      }
    } catch (e) {
      developer.log('Migration road error: $e', name: 'FirestoreService');
    }

    developer.log('=== MIGRATION DONE: $migrated reviews migrated ===', name: 'FirestoreService');
    return migrated;
  }
}
