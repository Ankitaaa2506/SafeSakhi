import 'package:share_plus/share_plus.dart';

/// Generates and shares a formatted safety report via the native share sheet.
class SafetyReportShare {
  SafetyReportShare._();

  /// Share a safety report for a location (place or road).
  ///
  /// [name] — location or road name.
  /// [latitude] — center latitude.
  /// [longitude] — center longitude.
  /// [aiScore] — AI safety score (null if not yet analyzed).
  /// [aiSummary] — AI-generated summary (null if not yet analyzed).
  /// [reviewCount] — number of community reviews.
  static void share({
    required String name,
    required double latitude,
    required double longitude,
    int? aiScore,
    String? aiSummary,
    int reviewCount = 0,
  }) {
    final mapsLink = 'https://www.google.com/maps?q=$latitude,$longitude';
    final buffer = StringBuffer()
      ..writeln('📍 SafeSakhi Safety Report')
      ..writeln()
      ..writeln('Location:')
      ..writeln(name)
      ..writeln();

    if (aiScore != null) {
      buffer
        ..writeln('🛡️ AI Safety Score')
        ..writeln('$aiScore/100')
        ..writeln();

      if (aiSummary != null && aiSummary.isNotEmpty) {
        buffer
          ..writeln('📝 Community Summary')
          ..writeln(aiSummary)
          ..writeln();
      }
    }

    if (reviewCount > 0) {
      buffer
        ..writeln('👥 Community Reviews')
        ..writeln('$reviewCount')
        ..writeln();
    } else if (aiScore == null) {
      buffer
        ..writeln('No community reviews are available yet.')
        ..writeln()
        ..writeln('Be the first to contribute and help improve safety for everyone.')
        ..writeln();
    }

    buffer
      ..writeln('📍 Google Maps')
      ..writeln(mapsLink)
      ..writeln()
      ..writeln('Shared using SafeSakhi')
      ..writeln('Community-powered safer navigation.');

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'SafeSakhi Safety Report — $name',
      ),
    );
  }
}
