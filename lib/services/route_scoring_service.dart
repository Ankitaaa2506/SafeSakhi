import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'nearby_search_service.dart';
import '../models/search_result.dart';
import 'route_service.dart';
import 'zone_cache.dart';

/// Safety score breakdown for a route segment.
class RouteSafetyScore {
  final double policeProximity;   // 0–100: how close to police stations
  final double hospitalProximity; // 0–100: how close to hospitals
  final double communityReview;   // 0–100: community safety rating
  final double zoneSafety;        // 0–100: avoidance of danger zones
  final double overall;           // 0–100: weighted composite

  const RouteSafetyScore({
    required this.policeProximity,
    required this.hospitalProximity,
    required this.communityReview,
    required this.zoneSafety,
    required this.overall,
  });
}

/// Scores routes based on safety infrastructure proximity, community reviews,
/// and danger zone avoidance.
class RouteScoringService {
  static final RouteScoringService _instance = RouteScoringService._();
  factory RouteScoringService() => _instance;
  RouteScoringService._();

  final NearbySearchService _nearbySearch = NearbySearchService();

  // Weights for composite score
  static const double _wPolice = 0.25;
  static const double _wHospital = 0.20;
  static const double _wCommunity = 0.30;
  static const double _wZone = 0.25;

  /// Sample points along a route at [sampleDistance] meter intervals.
  List<LatLng> _sampleRoute(List<LatLng> points, double sampleDistance) {
    if (points.length < 2) return points;

    final sampled = <LatLng>[points.first];
    double accumulated = 0;

    for (int i = 1; i < points.length; i++) {
      final d = _haversine(points[i - 1], points[i]);
      accumulated += d;
      if (accumulated >= sampleDistance) {
        sampled.add(points[i]);
        accumulated = 0;
      }
    }

    // Always include the last point
    if (sampled.last != points.last) {
      sampled.add(points.last);
    }

    return sampled;
  }

  /// Score police proximity: closer = higher score.
  Future<double> _scorePoliceProximity(List<LatLng> samplePoints) async {
    if (samplePoints.isEmpty) return 50.0; // neutral if no data

    double totalScore = 0;
    int count = 0;

    for (final point in samplePoints) {
      try {
        final results = await _nearbySearch.searchCategory(
          SearchCategory.police,
          lat: point.latitude,
          lng: point.longitude,
        );
        if (results.isNotEmpty) {
          final nearestDist = results.first.distance ?? 5000;
          // Score: 100 if within 100m, 0 if > 2000m, linear in between
          final score = (100 - (nearestDist / 20).clamp(0, 100)).toDouble();
          totalScore += score;
        }
      } catch (_) {}
      count++;
      if (count >= 3) break; // Limit API calls
    }

    return count > 0 ? totalScore / count : 50.0;
  }

  /// Score hospital proximity: closer = higher score.
  Future<double> _scoreHospitalProximity(List<LatLng> samplePoints) async {
    if (samplePoints.isEmpty) return 50.0;

    double totalScore = 0;
    int count = 0;

    for (final point in samplePoints) {
      try {
        final results = await _nearbySearch.searchCategory(
          SearchCategory.hospital,
          lat: point.latitude,
          lng: point.longitude,
        );
        if (results.isNotEmpty) {
          final nearestDist = results.first.distance ?? 5000;
          final score = (100 - (nearestDist / 50).clamp(0, 100)).toDouble();
          totalScore += score;
        }
      } catch (_) {}
      count++;
      if (count >= 3) break;
    }

    return count > 0 ? totalScore / count : 50.0;
  }

  /// Score zone safety based on danger zones along the route.
  double _scoreZoneSafety(List<LatLng> samplePoints, List<SafetyZone> zones) {
    if (samplePoints.isEmpty || zones.isEmpty) return 70.0;

    int dangerCount = 0;
    int moderateCount = 0;
    int safeCount = 0;

    for (final point in samplePoints) {
      for (final zone in zones) {
        final dist = _haversine(point, LatLng(zone.lat, zone.lng));
        if (dist <= zone.radius + 50) {
          switch (zone.level) {
            case ZoneLevel.danger:
              dangerCount++;
              break;
            case ZoneLevel.moderate:
              moderateCount++;
              break;
            case ZoneLevel.safe:
              safeCount++;
              break;
          }
        }
      }
    }

    // Start at 70, penalize for danger/moderate, bonus for safe
    double score = 70.0;
    score -= dangerCount * 15.0;
    score -= moderateCount * 5.0;
    score += safeCount * 5.0;
    return score.clamp(0.0, 100.0);
  }

  /// Calculate composite safety score for a route.
  Future<RouteSafetyScore> scoreRoute({
    required List<LatLng> routePoints,
    required VehicleMode vehicle,
  }) async {
    final samplePoints = _sampleRoute(routePoints, 500); // Sample every 500m
    final zones = ZoneCache.instance.zones;

    // Run scoring in parallel where possible
    final policeFuture = _scorePoliceProximity(samplePoints);
    final hospitalFuture = _scoreHospitalProximity(samplePoints);

    final police = await policeFuture;
    final hospital = await hospitalFuture;
    final zone = _scoreZoneSafety(samplePoints, zones);

    // Community review score is neutral (50) since we don't have route-specific reviews
    // In a real implementation, you'd query reviews near sample points
    const community = 50.0;

    final overall = (police * _wPolice +
            hospital * _wHospital +
            community * _wCommunity +
            zone * _wZone)
        .clamp(0.0, 100.0);

    return RouteSafetyScore(
      policeProximity: police,
      hospitalProximity: hospital,
      communityReview: community,
      zoneSafety: zone,
      overall: overall,
    );
  }

  /// Quick zone-only scoring (no API calls) for fast comparison.
  double quickScore(List<LatLng> routePoints) {
    final zones = ZoneCache.instance.zones;
    final samplePoints = _sampleRoute(routePoints, 1000);
    return _scoreZoneSafety(samplePoints, zones);
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }
}
