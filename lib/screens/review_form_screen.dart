import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/gemini_safety_service.dart';
import '../theme/constants.dart';

enum ReviewTargetType { place, road }

class ReviewFormScreen extends StatefulWidget {
  final String targetId;
  final String targetName;
  final ReviewTargetType targetType;
  final double? latitude;
  final double? longitude;

  const ReviewFormScreen({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.targetType,
    this.latitude,
    this.longitude,
  });

  @override
  State<ReviewFormScreen> createState() => _ReviewFormScreenState();
}

class _ReviewFormScreenState extends State<ReviewFormScreen> {
  int _overallSafety = 0;
  String? _timeOfDay;
  String? _lighting;
  String? _crowd;
  String? _policePresence;
  String? _walkAlone;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _overallSafety > 0 &&
      _timeOfDay != null &&
      _lighting != null &&
      _crowd != null &&
      _policePresence != null &&
      _walkAlone != null;

  bool _isAnalyzing = false;

  Future<void> _submit() async {
    if (!_isValid || _isSubmitting) return;

    print('[REVIEW DEBUG] === _submit START ===');
    print('[REVIEW DEBUG] targetId: "${widget.targetId}"');
    print('[REVIEW DEBUG] targetName: "${widget.targetName}"');
    print('[REVIEW DEBUG] targetType: ${widget.targetType}');

    setState(() => _isSubmitting = true);

    try {
      final auth = context.read<AuthProvider>();
      final user = auth.appUser;

      print('[REVIEW DEBUG] User: uid=${user?.uid}, name=${user?.displayName}');

      final isPlace = widget.targetType == ReviewTargetType.place;
      final reviewData = <String, dynamic>{
        'userId': user?.uid ?? 'anonymous',
        'userName': user?.displayName ?? 'Anonymous',
        'userPhotoUrl': user?.photoUrl ?? '',
        'overallSafety': _overallSafety,
        'timeOfDay': _timeOfDay,
        'lighting': _lighting,
        'crowd': _crowd,
        'policePresence': _policePresence,
        'walkingAlone': _walkAlone,
        'comment': _commentController.text.trim(),
        'reviewType': isPlace ? 'place' : 'road',
        'placeName': isPlace ? widget.targetName : null,
        'roadName': isPlace ? null : widget.targetName,
      };

      if (widget.latitude != null && widget.longitude != null) {
        reviewData['latitude'] = widget.latitude;
        reviewData['longitude'] = widget.longitude;
        reviewData['location'] = GeoPoint(widget.latitude!, widget.longitude!);
      }

      print('[REVIEW DEBUG] reviewData: $reviewData');

      if (widget.targetType == ReviewTargetType.place) {
        print('[REVIEW DEBUG] Saving place review to Firestore...');
        await FirestoreService().addPlaceReview(widget.targetId, reviewData);
        print('[REVIEW DEBUG] Place review saved successfully');
      } else {
        print('[REVIEW DEBUG] Saving road review to Firestore...');
        await FirestoreService().addRoadReview(widget.targetId, reviewData);
        print('[REVIEW DEBUG] Road review saved successfully');
      }

      if (!mounted) {
        print('[REVIEW DEBUG] ABORT: widget not mounted after Firestore save');
        return;
      }

      if (widget.targetType == ReviewTargetType.place) {
        print('[REVIEW DEBUG] Starting Gemini analysis...');
        setState(() {
          _isSubmitting = false;
          _isAnalyzing = true;
        });

        try {
          print('[REVIEW DEBUG] Calling GeminiSafetyService().analyzePlace("${widget.targetId}")');
          await GeminiSafetyService().analyzePlace(widget.targetId);
          print('[REVIEW DEBUG] Gemini analysis completed');
        } catch (e) {
          print('[REVIEW DEBUG] Gemini analysis FAILED: $e');
        }

        if (!mounted) {
          print('[REVIEW DEBUG] ABORT: widget not mounted after Gemini');
          return;
        }
        setState(() => _isAnalyzing = false);
      } else {
        print('[REVIEW DEBUG] Starting road Gemini analysis...');
        setState(() {
          _isSubmitting = false;
          _isAnalyzing = true;
        });

        try {
          await GeminiSafetyService().analyzeRoad(widget.targetId);
          print('[REVIEW DEBUG] Road Gemini analysis completed');
        } catch (e) {
          print('[REVIEW DEBUG] Road Gemini analysis FAILED: $e');
        }

        if (!mounted) return;
        setState(() => _isAnalyzing = false);
      }

      print('[REVIEW DEBUG] Setting _submitted = true');
      setState(() => _submitted = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Review submitted — thank you!'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.errorRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          'Add Review',
          style: AppStyles.appBarTitleStyle,
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlaceHeader(),
            const SizedBox(height: 20),
            _buildSection(
              title: 'How safe did you feel?',
              required: true,
              child: _buildStarRating(),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'When were you here?',
              required: true,
              child: _buildChoiceChips(
                options: const ['Morning', 'Afternoon', 'Evening', 'Night'],
                selected: _timeOfDay,
                onSelected: (v) => setState(() => _timeOfDay = v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Lighting',
              required: true,
              child: _buildChoiceChips(
                options: const ['Good', 'Average', 'Poor'],
                selected: _lighting,
                onSelected: (v) => setState(() => _lighting = v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Crowd',
              required: true,
              child: _buildChoiceChips(
                options: const ['Busy', 'Moderate', 'Isolated'],
                selected: _crowd,
                onSelected: (v) => setState(() => _crowd = v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Police Presence',
              required: true,
              child: _buildChoiceChips(
                options: const ['Frequent', 'Occasional', 'None'],
                selected: _policePresence,
                onSelected: (v) => setState(() => _policePresence = v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Would you feel comfortable walking here alone?',
              required: true,
              child: _buildChoiceChips(
                options: const ['Yes', 'Maybe', 'No'],
                selected: _walkAlone,
                onSelected: (v) => setState(() => _walkAlone = v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'Share your experience',
              required: false,
              child: _buildCommentField(),
            ),
            const SizedBox(height: 24),
            _buildValidationHint(),
            const SizedBox(height: 12),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppStyles.standardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              widget.targetType == ReviewTargetType.place
                  ? Icons.place_outlined
                  : Icons.route,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.targetName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.targetType == ReviewTargetType.place
                      ? 'Place Review'
                      : 'Road Review',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool required,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              children: required
                  ? const [
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.errorRed,
                        ),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final isSelected = starIndex <= _overallSafety;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _overallSafety = starIndex);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 44,
              color: isSelected
                  ? const Color(0xFFF57F17)
                  : AppColors.textHint.withValues(alpha: 0.4),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildChoiceChips({
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option == selected;
        return AnimatedScale(
          scale: isSelected ? 1.0 : 0.97,
          duration: const Duration(milliseconds: 150),
          child: ChoiceChip(
            label: Text(option),
            selected: isSelected,
            onSelected: (_) {
              HapticFeedback.lightImpact();
              onSelected(option);
            },
            selectedColor: AppColors.primaryBlue,
            backgroundColor: AppColors.chipBackground,
            labelStyle: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCommentField() {
    return TextField(
      controller: _commentController,
      maxLength: 250,
      maxLines: 3,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Share your experience (optional)',
        hintStyle: TextStyle(
          color: AppColors.textHint.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        filled: true,
        fillColor: AppColors.chipBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        counterStyle: TextStyle(
          fontSize: 12,
          color: AppColors.textHint,
        ),
      ),
    );
  }

  Widget _buildValidationHint() {
    if (_isValid || _submitted) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFF57F17)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please fill all required fields to submit',
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFFF57F17),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: _isValid && !_isSubmitting && !_isAnalyzing ? _submit : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : _isAnalyzing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Updating AI Safety Analysis...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Submit Review',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
      ),
    );
  }
}
