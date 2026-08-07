import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/constants.dart';

class LocationButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const LocationButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      scale: isLoading ? 0.96 : 1,
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: isLoading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onPressed();
                },
          customBorder: const CircleBorder(),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isLoading ? null : AppColors.brandGradient,
              color: isLoading
                  ? AppColors.white.withValues(alpha: 0.96)
                  : null,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.75),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.primaryBlue),
                    ),
                  )
                : const Icon(
                    Icons.my_location,
                    color: AppColors.white,
                    size: 23,
                  ),
          ),
        ),
      ),
    );
  }
}
