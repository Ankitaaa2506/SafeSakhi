import 'package:latlong2/latlong.dart';

enum VehicleMode { drive, walk, cycle }

extension VehicleModeExtension on VehicleMode {
  String get orsProfile {
    switch (this) {
      case VehicleMode.drive:
        return 'driving-car';
      case VehicleMode.walk:
        return 'foot-walking';
      case VehicleMode.cycle:
        return 'cycling-regular';
    }
  }

  String get label {
    switch (this) {
      case VehicleMode.drive:
        return 'Drive';
      case VehicleMode.walk:
        return 'Walk';
      case VehicleMode.cycle:
        return 'Cycle';
    }
  }

  double get speedKmh {
    switch (this) {
      case VehicleMode.drive:
        return 40.0;
      case VehicleMode.walk:
        return 5.0;
      case VehicleMode.cycle:
        return 15.0;
    }
  }
}

/// A decoded route with distance and duration metadata.
class RouteData {
  final List<LatLng> points;
  final double distanceMeters;

  /// Actual ORS duration in seconds.
  final double durationSeconds;

  const RouteData({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  /// Formatted duration: "5min 30seconds" or "1h 15min".
  String durationTextFor(VehicleMode mode) {
    final totalSecs = durationSecondsFor(mode).round();
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    if (mins < 60) return '${mins}min ${secs}seconds';
    final hrs = mins ~/ 60;
    final remainMins = mins % 60;
    return '${hrs}h ${remainMins}min';
  }

  /// Instant ETA when switching modes — uses distance ÷ mode speed.
  double durationSecondsFor(VehicleMode mode) {
    final speedMps = mode.speedKmh * 1000 / 3600;
    return distanceMeters / speedMps;
  }

  /// Estimated time of arrival (e.g. "3:45 PM").
  String get etaText {
    final arrival = DateTime.now().add(Duration(seconds: durationSeconds.round()));
    final h = arrival.hour;
    final m = arrival.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $period';
  }
}
