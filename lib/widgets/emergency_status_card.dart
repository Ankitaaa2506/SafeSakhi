import 'package:flutter/material.dart';

class EmergencyStatusCard extends StatelessWidget {
  final bool gpsReady;
  final bool sirenActive;
  final bool contactReady;
  final bool locationReady;
  final bool smsReady;
  final bool vibrationActive;

  const EmergencyStatusCard({
    super.key,
    this.gpsReady = false,
    this.sirenActive = false,
    this.contactReady = false,
    this.locationReady = false,
    this.smsReady = false,
    this.vibrationActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergency Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _statusRow('GPS Connected', gpsReady),
          const SizedBox(height: 8),
          _statusRow('Emergency Contact Ready', contactReady),
          const SizedBox(height: 8),
          _statusRow('Location Ready', locationReady),
          const SizedBox(height: 8),
          _statusRow('SMS Ready', smsReady),
          const SizedBox(height: 8),
          _statusRow('Siren Active', sirenActive),
          const SizedBox(height: 8),
          _statusRow('Vibration Active', vibrationActive),
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool ready) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: ready ? const Color(0xFF4CAF50) : Colors.white24,
            shape: BoxShape.circle,
            boxShadow: ready
                ? [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                      blurRadius: 6,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: ready ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: ready ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
