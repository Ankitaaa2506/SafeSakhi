import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/constants.dart';
import '../models/search_result.dart';
import '../screens/dashboard_screen.dart';
import '../screens/home_screen.dart';
import '../screens/sos_countdown_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/auth_popup.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  SearchCategory? _pendingCategory;

  void _onTap(int index) {
    if (index == 2) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SosCountdownScreen()),
      );
      return;
    }
    if (index == 4) {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) {
        showAuthPopup(context);
        return;
      }
    }
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  void _onQuickAction(SearchCategory category) {
    setState(() {
      _pendingCategory = category;
      _currentIndex = 1;
    });
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return DashboardScreen(onQuickAction: _onQuickAction);
      case 1:
        return HomeScreen(onCategoryFromDashboard: _pendingCategory);
      case 3:
        return const AlertsScreen();
      case 4:
        return const ProfileScreen();
      default:
        return DashboardScreen(onQuickAction: _onQuickAction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottom),
        color: Colors.transparent,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: AppColors.ink.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
              BoxShadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 1, offset: const Offset(0, -1)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              _buildNavItem(1, Icons.map_outlined, Icons.map_rounded, 'Map'),
              _buildSosButton(),
              _buildNavItem(3, Icons.notifications_none_rounded, Icons.notifications_rounded, 'Alerts'),
              _buildNavItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlined, IconData filled, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryBlue.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? filled : outlined,
                size: 24,
                color: isSelected ? AppColors.primaryBlue : AppColors.textHint,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primaryBlue : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosButton() {
    return GestureDetector(
      onTap: () => _onTap(2),
      child: Container(
        width: 60,
        height: 60,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: AppColors.sosGradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.sosRed.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sos_rounded, color: Colors.white, size: 22),
            Text('SOS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
