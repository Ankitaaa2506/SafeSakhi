import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/constants.dart';

class SosButton extends StatefulWidget {
  final VoidCallback onPressed;

  const SosButton({super.key, required this.onPressed});

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _pressController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _pressAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pressAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _pressAnimation]),
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value * _pressAnimation.value,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sosRed.withValues(alpha: 0.13),
                ),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTapDown: (_) => _pressController.forward(),
                  onTapCancel: () => _pressController.reverse(),
                  onTapUp: (_) => _pressController.reverse(),
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    widget.onPressed();
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 63,
                    height: 63,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.sosGradient,
                      boxShadow: AppStyles.sosShadow,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.emergency, color: Colors.white, size: 23),
                        Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
