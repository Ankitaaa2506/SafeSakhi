import 'package:flutter/material.dart';
import '../models/search_result.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF2457E6);
  static const Color primaryBlueDark = Color(0xFF173AAE);
  static const Color primaryTeal = Color(0xFF00A7A0);
  static const Color primaryViolet = Color(0xFF7C3AED);
  static const Color sosRed = Color(0xFFE9344E);
  static const Color sosRedDark = Color(0xFF9F1239);
  static const Color warningAmber = Color(0xFFFFB020);
  static const Color safeGreen = Color(0xFF13A66B);
  static const Color errorRed = Color(0xFFE9344E);
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color ink = Color(0xFF111827);
  static const Color textPrimary = Color(0xFF172033);
  static const Color textSecondary = Color(0xFF5C667A);
  static const Color textHint = Color(0xFF98A2B3);
  static const Color searchBackground = Colors.white;
  static const Color bottomNavBackground = Colors.white;
  static const Color chipBackground = Color(0xFFF7F9FC);
  static const Color chipActiveBackground = Color(0xFFEAF0FF);
  static const Color surface = Color(0xFFF6F8FC);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE8ECF3);
  static const Color scaffoldBackground = Color(0xFFF6F8FC);
  static const Color borderColor = Color(0xFFDDE3ED);
  static const Color glassBorder = Color(0x40FFFFFF);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF2457E6), Color(0xFF00A7A0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sosGradient = LinearGradient(
    colors: [Color(0xFFFF4D6D), Color(0xFFE9344E), Color(0xFF9F1239)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppStyles {
  static final BorderRadius searchBarRadius = BorderRadius.circular(24.0);
  static final BorderRadius bottomNavRadius = BorderRadius.circular(26.0);
  static final BorderRadius bottomNavTopRadius = BorderRadius.only(
    topLeft: Radius.circular(20.0),
    topRight: Radius.circular(20.0),
  );
  static final BorderRadius chipRadius = BorderRadius.circular(18.0);
  static final BorderRadius cardRadius = BorderRadius.circular(18.0);
  static final BorderRadius buttonRadius = BorderRadius.circular(16.0);

  static const TextStyle headingStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static const TextStyle appBarTitleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static final List<BoxShadow> standardShadow = [
    BoxShadow(
      color: const Color(0xFF172033).withValues(alpha: 0.10),
      blurRadius: 18,
      offset: const Offset(0, 8),
    )
  ];

  static final List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: const Color(0xFF172033).withValues(alpha: 0.14),
      blurRadius: 30,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.70),
      blurRadius: 1,
      offset: const Offset(0, -1),
    ),
  ];

  static final List<BoxShadow> sosShadow = [
    BoxShadow(
      color: AppColors.sosRed.withValues(alpha: 0.38),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];
}

class CategoryConfig {
  static final Map<SearchCategory, Color> categoryColors = {
    SearchCategory.hospital: const Color(0xFFE53935),
    SearchCategory.police: const Color(0xFF1E88E5),
    SearchCategory.pharmacy: const Color(0xFFFF8F00),
    SearchCategory.atm: const Color(0xFF8E24AA),
    SearchCategory.restaurant: const Color(0xFFFF8F00),
    SearchCategory.cafe: const Color(0xFF6D4C41),
    SearchCategory.mall: const Color(0xFFD81B60),
    SearchCategory.petrolPump: const Color(0xFF5C6BC0),
    SearchCategory.busStand: const Color(0xFF00897B),
    SearchCategory.railwayStation: const Color(0xFF546E7A),
    SearchCategory.school: const Color(0xFF43A047),
    SearchCategory.college: const Color(0xFF1565C0),
    SearchCategory.university: const Color(0xFF1565C0),
    SearchCategory.bank: const Color(0xFF2E7D32),
    SearchCategory.hotel: const Color(0xFFAD1457),
    SearchCategory.park: const Color(0xFF2E7D32),
    SearchCategory.safeArea: const Color(0xFF43A047),
    SearchCategory.womenHelp: const Color(0xFF8E24AA),
    SearchCategory.general: const Color(0xFF757575),
  };

  static const List<SearchCategory> chipCategories = [
    SearchCategory.police,
    SearchCategory.hospital,
    SearchCategory.safeArea,
    SearchCategory.pharmacy,
    SearchCategory.womenHelp,
  ];
}
