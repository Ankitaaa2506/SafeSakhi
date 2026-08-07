import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/search_result.dart';
import '../services/firestore_service.dart';
import '../theme/constants.dart';
import 'sheet_shared.dart';

class PremiumBottomSheet extends StatefulWidget {
  final SearchResult result;
  final VoidCallback? onNavigate;
  final VoidCallback? onAddReview;
  final VoidCallback? onViewReviews;
  final VoidCallback? onShare;
  final VoidCallback? onClose;

  const PremiumBottomSheet({
    super.key,
    required this.result,
    this.onNavigate,
    this.onAddReview,
    this.onViewReviews,
    this.onShare,
    this.onClose,
  });

  @override
  State<PremiumBottomSheet> createState() => _PremiumBottomSheetState();
}

class _PremiumBottomSheetState extends State<PremiumBottomSheet>
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
      stream: FirestoreService().streamPlaceDoc(widget.result.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        if (!snapshot.data!.exists) {
          return _buildNoReviews();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final reviewCount = data?['reviewCount'] as int? ?? 0;
        final aiScore = data?['score'];
        final aiSummary = data?['summary'];

        if (reviewCount == 0) {
          return _buildNoReviews();
        }

        if (aiScore == null) {
          return _buildAnalyzing();
        }

        final score = aiScore is int ? aiScore : (aiScore as num).toInt();
        final summary = aiSummary as String?;

        return Column(
          children: [
            SafetyScoreCard(score: score, summary: summary),
            if (summary != null && summary.isNotEmpty) ...[
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
                      summary,
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
            'Analyzing community reviews...',
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
    final categoryColor =
        CategoryConfig.categoryColors[widget.result.category] ?? Colors.grey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.result.name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
            height: 1.25,
            letterSpacing: -0.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildPlaceChip(categoryColor),
            if (widget.result.displayDistance.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildDistanceChip(),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceChip(Color categoryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        SearchResult.categoryName(widget.result.category),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: categoryColor,
        ),
      ),
    );
  }

  Widget _buildDistanceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.chipBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.near_me, size: 13, color: AppColors.textHint),
          const SizedBox(width: 4),
          Text(
            widget.result.displayDistance,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
