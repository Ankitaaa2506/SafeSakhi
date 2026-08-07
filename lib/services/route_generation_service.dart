import 'dart:math';
import 'dart:developer' as developer;
import 'package:latlong2/latlong.dart';
import 'route_service.dart';
import 'route_engine.dart';
import 'route_scoring_service.dart';
import 'zone_cache.dart';

class GeneratedRoute {
  final RouteData route;
  final String label;
  final int colorIndex;
  final int zonesAvoided;
  final int zonesCrossed;
  final double riskScore;
  final List<SafetyZone> warningZones;
  final String timeDeltaText;

  const GeneratedRoute({
    required this.route,
    required this.label,
    required this.colorIndex,
    required this.zonesAvoided,
    required this.zonesCrossed,
    required this.riskScore,
    this.warningZones = const [],
    this.timeDeltaText = '',
  });
}

/// SafeSakhi Routing Engine v8 — ORS Alternatives + Safety Scoring.
///
/// Flow:
/// 1. Fetch ORS alternative routes (up to 3)
/// 2. If ORS returns < 3, generate waypoint-based fallbacks
/// 3. Apply diversity filtering (70% overlap threshold)
/// 4. Score routes by safety infrastructure
/// 5. Assign labels: Safest, Safe, Risky
/// 6. Annotate with time deltas vs. the actual fastest route
class RouteGenerationService {
  static const _tag = 'SafeSakhi.Routes';

  final RouteEngine _engine;
  final RouteScoringService _scoring;

  RouteGenerationService({
    RouteEngine? engine,
    RouteScoringService? scoring,
  })  : _engine = engine ?? RouteEngine(),
        _scoring = scoring ?? RouteScoringService();

  Future<List<GeneratedRoute>> generateRoutes({
    required LatLng origin,
    required LatLng destination,
    required VehicleMode vehicle,
  }) async {
    final totalSw = Stopwatch()..start();

    // ── Phase 1: Fetch ORS alternatives ──
    final fetchSw = Stopwatch()..start();
    final orsRoutes = await _engine.fetchOrsAlternatives(
      origin: origin,
      destination: destination,
      vehicle: vehicle,
      maxRoutes: 3,
    );
    fetchSw.stop();

    developer.log('ORS returned ${orsRoutes.length} routes in ${fetchSw.elapsedMilliseconds}ms',
        name: _tag);

    // ── Phase 2: Generate fallbacks if ORS returned < 3 ──
    final fallbackSw = Stopwatch()..start();
    var allRoutes = List<RouteData>.from(orsRoutes);

    if (allRoutes.isEmpty) {
      // ORS failed entirely — get base route and generate waypoints
      final baseRoute = await _engine.fetchBaseRoute(
        origin: origin,
        destination: destination,
        vehicle: vehicle,
      );
      allRoutes = [baseRoute];

      final waypoints = _engine.getWaypoints(baseRoute.points, count: 3);
      for (final wp in waypoints) {
        try {
          final route = await _engine.fetchViaWaypoint(
            origin: origin,
            destination: destination,
            waypoint: wp,
            vehicle: vehicle,
          );
          allRoutes.add(route);
        } catch (_) {}
      }
    } else if (allRoutes.length < 3) {
      // ORS returned 1-2 routes — generate fallbacks
      final baseRoute = allRoutes.first;
      final waypoints = _engine.getWaypoints(baseRoute.points, count: 3);

      for (final wp in waypoints) {
        if (allRoutes.length >= 3) break;
        try {
          final route = await _engine.fetchViaWaypoint(
            origin: origin,
            destination: destination,
            waypoint: wp,
            vehicle: vehicle,
          );
          allRoutes.add(route);
        } catch (_) {}
      }
    }
    fallbackSw.stop();

    // ── Phase 3: Apply diversity filtering ──
    final filterSw = Stopwatch()..start();
    final baseRoute = allRoutes.first;
    final filtered = _engine.filterByDiversity(allRoutes);
    final detourFiltered = _engine.filterByDetour(filtered, baseRoute);
    filterSw.stop();

    developer.log(
        'After filtering: ${detourFiltered.length} routes (from ${allRoutes.length})',
        name: _tag);

    // ── Phase 4: Score routes ──
    final scoreSw = Stopwatch()..start();
    final scores = <double>[];
    for (final route in detourFiltered) {
      final score = _scoring.quickScore(route.points);
      scores.add(score);
    }
    scoreSw.stop();

    // ── Phase 5: Assign labels by safety score ──
    // Sort by safety score (highest = safest), then label them
    // Safest (green) → Safe (yellow) → Risky (red).
    final indexed = List.generate(detourFiltered.length, (i) => i);
    indexed.sort((a, b) => scores[b].compareTo(scores[a]));

    final zones = ZoneCache.instance.zones;
    const labelOrder = ['Safest', 'Safe', 'Risky'];
    final results = <GeneratedRoute>[];

    for (var i = 0; i < indexed.length; i++) {
      final route = detourFiltered[indexed[i]];
      final label = labelOrder[i < labelOrder.length ? i : labelOrder.length - 1];
      final colorIdx = label == 'Safest' ? 0 : label == 'Safe' ? 1 : 2;
      results.add(_buildResult(route, label, colorIdx, zones, baseRoute));
    }

    // Ensure we have at least 1 route
    if (results.isEmpty && detourFiltered.isNotEmpty) {
      results.add(_buildResult(
          detourFiltered.first, 'Risky', 2, zones, baseRoute));
    }

    // ── Phase 6: Time delta annotation against the truly fastest route ──
    final fastestSecs = results
        .map((r) => r.route.durationSecondsFor(vehicle))
        .reduce(min);
    final annotated =
        results.map((r) => _withDelta(r, fastestSecs, vehicle)).toList();

    totalSw.stop();

    // ── Timing report ──
    developer.log('''
══════ ROUTING PROFILE v8 ══════
ORS Fetch ................. ${fetchSw.elapsedMilliseconds} ms
Fallback Generation ....... ${fallbackSw.elapsedMilliseconds} ms
Diversity Filtering ....... ${filterSw.elapsedMilliseconds} ms
Safety Scoring ............ ${scoreSw.elapsedMilliseconds} ms
TOTAL ..................... ${totalSw.elapsedMilliseconds} ms
══════ ROUTES ══════════════════
ORS Routes ................ ${orsRoutes.length}
After Fallback ............ ${allRoutes.length}
After Diversity ........... ${detourFiltered.length}
Final Options ............. ${annotated.length}
ORS Requests .............. ${_engine.orsCount}
═══════════════════════════════
''', name: _tag);

    for (final r in annotated) {
      developer.log(
        '${r.label}: ${r.route.durationSeconds.round()}s, ${r.route.distanceText}, risk=${r.riskScore.toStringAsFixed(0)}',
        name: _tag,
      );
    }

    return annotated;
  }

  // ── Result builder ──

  GeneratedRoute _buildResult(
    RouteData route,
    String label,
    int colorIndex,
    List<SafetyZone> zones,
    RouteData baseRoute,
  ) {
    final routeDanger = _countDangerOnRoute(route.points, zones);
    final baseDanger = _countDangerOnRoute(baseRoute.points, zones);
    final avoided = max(0, baseDanger - routeDanger);
    return GeneratedRoute(
      route: route,
      label: label,
      colorIndex: colorIndex,
      zonesAvoided: avoided,
      zonesCrossed: routeDanger,
      riskScore: routeDanger * 100.0,
      warningZones: _dangerZonesOnRoute(route.points, zones),
    );
  }

  // ── Route classification ──

  int _countDangerOnRoute(List<LatLng> points, List<SafetyZone> zones) {
    final hit = <String>{};
    final step = max(1, points.length ~/ 60);
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      for (final zone in zones) {
        if (hit.contains(zone.id)) continue;
        if (zone.level == ZoneLevel.safe) continue;
        final d = _haversine(p, LatLng(zone.lat, zone.lng));
        if (d <= zone.radius + 15.0) hit.add(zone.id);
      }
    }
    return hit.length;
  }

  List<SafetyZone> _dangerZonesOnRoute(List<LatLng> points, List<SafetyZone> zones) {
    final hit = <String, SafetyZone>{};
    final step = max(1, points.length ~/ 60);
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      for (final zone in zones) {
        if (hit.containsKey(zone.id)) continue;
        if (zone.level == ZoneLevel.safe) continue;
        final d = _haversine(p, LatLng(zone.lat, zone.lng));
        if (d <= zone.radius + 15.0) hit[zone.id] = zone;
      }
    }
    return hit.values.toList();
  }

  // ── Time delta ──

GeneratedRoute _withDelta(
    GeneratedRoute r, double fastestSecs, VehicleMode vehicle) {
  final diffSecs = r.route.durationSecondsFor(vehicle) - fastestSecs;
  final text = diffSecs <= 5 ? 'Fastest' : '+${_formatSeconds(diffSecs.round())}';
  return GeneratedRoute(
      route: r.route,
      label: r.label,
      colorIndex: r.colorIndex,
      zonesAvoided: r.zonesAvoided,
      zonesCrossed: r.zonesCrossed,
      riskScore: r.riskScore,
      warningZones: r.warningZones,
      timeDeltaText: text,
    );
  }

  // ── Haversine ──

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

  static String _formatSeconds(int totalSecs) {
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    if (mins == 0) return '${secs}s';
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }
}
