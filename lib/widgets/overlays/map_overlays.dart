import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MapOverlays extends StatelessWidget {
  final double currentZoom;
  final double currentBearing;
  final bool isFollowingLocation;
  final VoidCallback onRecenter;
  final VoidCallback onNorthReset;

  const MapOverlays({
    super.key,
    required this.currentZoom,
    required this.currentBearing,
    this.isFollowingLocation = false,
    required this.onRecenter,
    required this.onNorthReset,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Compass (top-right) - always visible, positioned below category bar
        Positioned(
          top: 195,
          right: 16,
          child: _CompassButton(
            bearing: currentBearing,
            onTap: onNorthReset,
          ),
        ),

        // Scale bar (bottom-left)
        Positioned(
          bottom: 90,
          left: 16,
          child: _ScaleBar(zoom: currentZoom),
        ),
      ],
    );
  }
}

class _CompassButton extends StatelessWidget {
  final double bearing;
  final VoidCallback onTap;

  const _CompassButton({required this.bearing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: -bearing * math.pi / 180,
            child: const CustomPaint(
              painter: _CompassPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // North pointer (red)
    final northPaint = Paint()
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.fill;
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx - 4, center.dy)
      ..lineTo(center.dx + 4, center.dy)
      ..close();
    canvas.drawPath(northPath, northPaint);

    // South pointer (gray)
    final southPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.fill;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - 4, center.dy)
      ..lineTo(center.dx + 4, center.dy)
      ..close();
    canvas.drawPath(southPath, southPaint);

    // Center dot
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, dotPaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => true;
}

class _ScaleBar extends StatelessWidget {
  final double zoom;

  const _ScaleBar({required this.zoom});

  @override
  Widget build(BuildContext context) {
    final metersPerPx = 156543.03392 * math.cos(0) / math.pow(2, zoom);
    final screenWidth = MediaQuery.of(context).size.width;
    final barMeters = (screenWidth * 0.25 * metersPerPx).round();

    String label;
    if (barMeters >= 1000) {
      label = '${(barMeters / 1000).toStringAsFixed(1)} km';
    } else {
      label = '$barMeters m';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 3,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.black87, width: 1.5),
                right: BorderSide(color: Colors.black87, width: 1.5),
                top: BorderSide(color: Colors.black87, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
