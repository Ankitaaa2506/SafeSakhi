import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../services/firestore_service.dart';
import '../theme/constants.dart';
import 'sheet_shared.dart';

class RoadBottomSheet extends StatefulWidget {
  final String roadZoneId;
  final LatLng position;
  final String? roadName;
  final VoidCallback? onNavigate;
  final VoidCallback? onAddReview;
  final VoidCallback? onViewReviews;
  final VoidCallback? onShare;
  final VoidCallback? onClose;

  const RoadBottomSheet({
    super.key,
    required this.roadZoneId,
    required this.position,
    this.roadName,
    this.onNavigate,
    this.onAddReview,
    this.onViewReviews,
    this.onShare,
    this.onClose,
  });

  @override
  State<RoadBottomSheet> createState() => _RoadBottomSheetState();
}

class _RoadBottomSheetState extends State<RoadBottomSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    final (ctrl, fade, slide) = createSheetAnimations(this);
    _animController = ctrl;
    _fadeAnim = fade;
    _slideAnim = slide;
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildSheetAnimation(
      controller: _animController,
      fadeAnim: _fadeAnim,
      slideAnim: _slideAnim,
      child: _buildSheet(),
    );
  }

  Widget _buildSheet() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildAISection(),
                  const SizedBox(height: 24),
                  SheetPrimaryButtons(
                    onNavigate: widget.onNavigate,
                    onAddReview: widget.onAddReview,
                  ),
                  const SizedBox(height: 12),
                  SheetViewReviewsButton(onPressed: widget.onViewReviews),
                  const SizedBox(height: 20),
                  SheetBottomActions(
                    onShare: widget.onShare,
                    onClose: widget.onClose,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISection() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirestoreService().streamRoadZoneDoc(widget.roadZoneId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        if (!snapshot.data!.exists) {
          return _buildNoReviews();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final reviewCount = data?['reviewCount'] as int? ?? 0;
        final aiScore = data?['aiScore'];
        final aiSummary = data?['aiSummary'] as String?;

        if (reviewCount == 0) {
          return _buildNoReviews();
        }

        if (aiScore == null) {
          return _buildAnalyzing();
        }

        final score = aiScore is int ? aiScore : (aiScore as num).toInt();

        return Column(
          children: [
            SafetyScoreCard(score: score, summary: aiSummary),
            if (aiSummary != null && aiSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Summary',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      aiSummary,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNoReviews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.reviews_outlined, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'No community reviews yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Be the first to share your experience',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzing() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Analyzing community feedback...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.route,
                size: 22,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roadName ?? 'Road Segment',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                      height: 1.25,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Road',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
