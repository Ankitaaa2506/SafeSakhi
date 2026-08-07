import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/constants.dart';
import 'auth_popup.dart';

class SafetyScoreCard extends StatelessWidget {
  final int score;
  final String? summary;
  final String? roadLabel;

  const SafetyScoreCard({
    super.key,
    required this.score,
    this.summary,
    this.roadLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 90
        ? const Color(0xFF1B5E20)        // Dark green — Very Safe
        : score >= 75
            ? const Color(0xFF2E7D32)    // Green — Safe
            : score >= 60
                ? const Color(0xFFF9A825) // Yellow — Moderately Safe
                : score >= 40
                    ? const Color(0xFFF57F17) // Amber — Use Caution
                    : score >= 20
                        ? const Color(0xFFE65100) // Orange — Unsafe
                        : const Color(0xFFC62828); // Red — Very Unsafe

    final scoreTitle = score >= 90
        ? 'Very Safe'
        : score >= 75
            ? 'Safe'
            : score >= 60
                ? 'Moderately Safe'
                : score >= 40
                    ? 'Use Caution'
                    : score >= 20
                        ? 'Unsafe'
                        : 'Very Unsafe';

    final scoreLabel = roadLabel ??
        (score >= 90
            ? 'Excellent safety — well-lit, busy, well-patrolled'
            : score >= 75
                ? 'Good safety — decent lighting and foot traffic'
                : score >= 60
                    ? 'Moderate safety — some concerns, stay aware'
                    : score >= 40
                        ? 'Notable concerns — poor lighting or isolated'
                        : score >= 20
                            ? 'High risk — reports of danger, avoid if possible'
                            : 'Very dangerous — strong evidence of threats');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scoreColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 4.5,
                    backgroundColor: scoreColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Safety Score',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  scoreTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scoreLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SheetPrimaryButtons extends StatelessWidget {
  final VoidCallback? onNavigate;
  final VoidCallback? onAddReview;

  const SheetPrimaryButtons({
    super.key,
    this.onNavigate,
    this.onAddReview,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;

    return Column(
      children: [
        if (onNavigate != null) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onNavigate,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Directions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 52,
          child: isLoggedIn
              ? FilledButton(
                  onPressed: onAddReview,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B1FA2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rate_review, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Add Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    showAuthPopup(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.grey.shade600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Sign in to Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class SheetViewReviewsButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SheetViewReviewsButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          side: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.reviews, size: 20),
            SizedBox(width: 10),
            Text(
              'View Reviews',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SheetBottomActions extends StatelessWidget {
  final VoidCallback? onShare;
  final VoidCallback? onClose;

  const SheetBottomActions({super.key, this.onShare, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: onShare,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton.tonal(
              onPressed: onClose ?? () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                backgroundColor: AppColors.chipBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget buildSheetAnimation({
  required AnimationController controller,
  required Animation<double> fadeAnim,
  required Animation<Offset> slideAnim,
  required Widget child,
}) {
  return AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      return FadeTransition(
        opacity: fadeAnim,
        child: SlideTransition(
          position: slideAnim,
          child: child,
        ),
      );
    },
  );
}

(AnimationController, Animation<double>, Animation<Offset>)
    createSheetAnimations(TickerProvider vsync) {
  final controller = AnimationController(
    vsync: vsync,
    duration: const Duration(milliseconds: 350),
  );

  final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ),
  );

  final slideAnim = Tween<Offset>(
    begin: const Offset(0, 0.15),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ),
  );

  return (controller, fadeAnim, slideAnim);
}

int generateSafetyScore(String name, dynamic category) {
  final cat = category;
  if (cat == null) return 40 + (name.hashCode % 30);

  final catName = cat.toString().split('.').last;

  switch (catName) {
    case 'hospital':
    case 'police':
      return 85 + (name.hashCode % 15);
    case 'atm':
    case 'bank':
      return 70 + (name.hashCode % 20);
    case 'pharmacy':
      return 65 + (name.hashCode % 20);
    case 'restaurant':
    case 'cafe':
      return 55 + (name.hashCode % 25);
    case 'mall':
    case 'hotel':
      return 60 + (name.hashCode % 25);
    default:
      return 40 + (name.hashCode % 30);
  }
}
