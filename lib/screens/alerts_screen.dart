import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/constants.dart';

enum AlertFilter { all, nearby, crime, weather, official }

enum AlertBadge { community, police, government, weather }

class _AlertData {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String time;
  final String? distance;
  final String description;
  final AlertBadge badge;
  final AlertFilter filter;

  const _AlertData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.time,
    this.distance,
    required this.description,
    required this.badge,
    required this.filter,
  });
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertFilter _selectedFilter = AlertFilter.all;

  static const _alerts = [
    _AlertData(
      icon: Icons.warning_amber_rounded,
      iconColor: Color(0xFFE53935),
      iconBg: Color(0xFFFCE4EC),
      title: 'Theft Alert',
      time: '2 hours ago',
      distance: '1.2 km away',
      description:
          'Multiple phone theft incidents reported near Railway Station. Stay alert and avoid isolated areas.',
      badge: AlertBadge.community,
      filter: AlertFilter.crime,
    ),
    _AlertData(
      icon: Icons.cloudy_snowing,
      iconColor: Color(0xFF1E88E5),
      iconBg: Color(0xFFE3F2FD),
      title: 'Heavy Rain Warning',
      time: 'Today',
      distance: null,
      description:
          'Heavy rainfall expected between 6 PM and 10 PM. Possible waterlogging in low-lying areas.',
      badge: AlertBadge.weather,
      filter: AlertFilter.weather,
    ),
    _AlertData(
      icon: Icons.local_police_outlined,
      iconColor: Color(0xFF3949AB),
      iconBg: Color(0xFFE8EAF6),
      title: 'Police Advisory',
      time: 'Today',
      distance: 'Bhagalpur',
      description:
          'Increased police patrolling near Kachahari Chowk during evening hours.',
      badge: AlertBadge.police,
      filter: AlertFilter.official,
    ),
    _AlertData(
      icon: Icons.thunderstorm_outlined,
      iconColor: Color(0xFF1E88E5),
      iconBg: Color(0xFFE3F2FD),
      title: 'Storm Alert',
      time: 'Tonight',
      distance: null,
      description:
          'Strong winds and thunderstorms expected. Avoid unnecessary travel.',
      badge: AlertBadge.weather,
      filter: AlertFilter.weather,
    ),
    _AlertData(
      icon: Icons.construction_rounded,
      iconColor: Color(0xFF43A047),
      iconBg: Color(0xFFE8F5E9),
      title: 'Traffic Advisory',
      time: 'Today',
      distance: null,
      description:
          'Main road near Bus Stand temporarily closed due to maintenance.',
      badge: AlertBadge.government,
      filter: AlertFilter.official,
    ),
  ];

  List<_AlertData> get _filteredAlerts {
    if (_selectedFilter == AlertFilter.all) return _alerts;
    return _alerts.where((a) => a.filter == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Safety Alerts',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Stay informed about your surroundings',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              _buildFilterChips(),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _filteredAlerts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _buildAlertCard(_filteredAlerts[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      (AlertFilter.all, 'All'),
      (AlertFilter.nearby, 'Nearby'),
      (AlertFilter.crime, 'Crime'),
      (AlertFilter.weather, 'Weather'),
      (AlertFilter.official, 'Official'),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedFilter = filter);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryBlue
                    : AppColors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryBlue
                      : AppColors.borderColor.withValues(alpha: 0.5),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlertCard(_AlertData alert) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: alert.iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(alert.icon, color: alert.iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _buildBadge(alert.badge),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      alert.time,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                    if (alert.distance != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.textHint.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        alert.distance!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  alert.description,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
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

  Widget _buildBadge(AlertBadge badge) {
    final (label, color) = switch (badge) {
      AlertBadge.community => ('Community', const Color(0xFF1E88E5)),
      AlertBadge.police => ('Police', const Color(0xFF3949AB)),
      AlertBadge.government => ('Government', const Color(0xFF43A047)),
      AlertBadge.weather => ('Weather', const Color(0xFF1E88E5)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
