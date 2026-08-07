import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import 'route_service.dart';

/// A raw route from ORS with metadata for scoring.
class RawRoute {
  final RouteData route;
  final double safetyScore;
  final String label;
  final int colorIndex;

  const RawRoute({
    required this.route,
    required this.safetyScore,
    required this.label,
    required this.colorIndex,
  });
}

/// Configuration for route generation.
class RouteEngineConfig {
  final double maxDetourFactor;
  final double overlapThreshold;
  final int sampleStep;

  const RouteEngineConfig({
    this.maxDetourFactor = 1.5,
    this.overlapThreshold = 0.70,
    this.sampleStep = 30,
  });

  static const defaultConfig = RouteEngineConfig();
}

/// Core routing engine that fetches ORS routes and applies diversity filtering.
class RouteEngine {
  static const _tag = 'SafeSakhi.RouteEngine';

  int _orsCount = 0;
  int get orsCount => _orsCount;

  final RouteEngineConfig config;
  final http.Client _httpClient;

  RouteEngine({
    this.config = RouteEngineConfig.defaultConfig,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Fetch alternative routes from ORS using the `alternative_routes` parameter.
  ///
  /// ORS may return 1-3 routes depending on road network.
  Future<List<RouteData>> fetchOrsAlternatives({
    required LatLng origin,
    required LatLng destination,
    required VehicleMode vehicle,
    int maxRoutes = 3,
  }) async {
    _orsCount++;
    final profile = vehicle.orsProfile;
    final url = 'https://api.openrouteservice.org/v2/directions/$profile/geojson';

    try {
      final response = await _httpClient
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json, application/geo+json',
              'Authorization': ApiKeys.openRouteService,
            },
            body: json.encode({
              'coordinates': [
                [origin.longitude, origin.latitude],
                [destination.longitude, destination.latitude],
              ],
              'instructions': false,
              'alternative_routes': {
                'target_count': maxRoutes,
                'share_factor': 0.65,
                'weight_factor': 1.4,
              },
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        developer.log('ORS error: ${response.statusCode}', name: _tag);
        return [];
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];

      return features.map((feature) {
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final coords = geometry['coordinates'] as List<dynamic>;
        final points =
            coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
        final summary = (feature['properties'] as Map<String, dynamic>)['summary']
            as Map<String, dynamic>;
        return RouteData(
          points: points,
          distanceMeters: (summary['distance'] as num).toDouble(),
          durationSeconds: (summary['duration'] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      developer.log('ORS fetch error: $e', name: _tag);
      return [];
    }
  }

  /// Fetch a single base route (no alternatives).
  Future<RouteData> fetchBaseRoute({
    required LatLng origin,
    required LatLng destination,
    required VehicleMode vehicle,
  }) async {
    _orsCount++;
    final profile = vehicle.orsProfile;
    final url = 'https://api.openrouteservice.org/v2/directions/$profile/geojson';

    try {
      final response = await _httpClient
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json, application/geo+json',
              'Authorization': ApiKeys.openRouteService,
            },
            body: json.encode({
              'coordinates': [
                [origin.longitude, origin.latitude],
                [destination.longitude, destination.latitude],
              ],
              'instructions': false,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return _parseOrsResponse(response);
    } catch (e) {
      developer.log('Base route error: $e', name: _tag);
      rethrow;
    }
  }

  /// Fetch a route via a waypoint (for fallback).
  Future<RouteData> fetchViaWaypoint({
    required LatLng origin,
    required LatLng destination,
    required LatLng waypoint,
    required VehicleMode vehicle,
  }) async {
    _orsCount++;
    final profile = vehicle.orsProfile;
    final url = 'https://api.openrouteservice.org/v2/directions/$profile/geojson';

    final response = await _httpClient
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json, application/geo+json',
            'Authorization': ApiKeys.openRouteService,
          },
          body: json.encode({
            'coordinates': [
              [origin.longitude, origin.latitude],
              [waypoint.longitude, waypoint.latitude],
              [destination.longitude, destination.latitude],
            ],
            'instructions': false,
          }),
        )
        .timeout(const Duration(seconds: 10));

    return _parseOrsResponse(response);
  }

  /// Filter routes by overlap — reject routes that share >threshold% geometry.
  List<RouteData> filterByDiversity(List<RouteData> routes) {
    if (routes.isEmpty) return [];
    if (routes.length == 1) return routes;

    final accepted = <RouteData>[routes.first];

    for (int i = 1; i < routes.length; i++) {
      final candidate = routes[i];
      bool tooSimilar = false;

      for (final existing in accepted) {
        final overlap = _overlapPercent(candidate, existing);
        if (overlap > config.overlapThreshold) {
          tooSimilar = true;
          break;
        }
      }

      if (!tooSimilar) {
        accepted.add(candidate);
      }
    }

    return accepted;
  }

  /// Filter routes by detour factor — reject routes that are >maxFactor
  /// longer than the base route.
  List<RouteData> filterByDetour(List<RouteData> routes, RouteData base) {
    if (base.distanceMeters <= 0) return routes;

    return routes.where((route) {
      final factor = route.distanceMeters / base.distanceMeters;
      return factor <= config.maxDetourFactor;
    }).toList();
  }

  /// Calculate overlap percentage between two routes (0–1).
  double _overlapPercent(RouteData a, RouteData b) {
    if (a.points.length < 2 || b.points.length < 2) return 0;

    int matched = 0;
    final step = max(1, a.points.length ~/ 40);
    final bStep = max(1, b.points.length ~/ 40);

    for (int i = 0; i < a.points.length; i += step) {
      final p = a.points[i];
      for (int j = 0; j < b.points.length; j += bStep) {
        if (_haversine(p, b.points[j]) < 30) {
          matched++;
          break;
        }
      }
    }

    final sampled = (a.points.length / step).ceil();
    return sampled > 0 ? matched / sampled : 0;
  }

  /// Get fallback waypoints from the route for generating alternatives.
  List<LatLng> getWaypoints(List<LatLng> points, {int count = 3}) {
    if (points.length < 4) return [];

    final step = points.length ~/ (count + 1);
    final waypoints = <LatLng>[];

    for (int i = 1; i <= count; i++) {
      final idx = (i * step).clamp(1, points.length - 2);
      waypoints.add(points[idx]);
    }

    return waypoints;
  }

  RouteData _parseOrsResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception('ORS ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) throw Exception('ORS: no features');

    final feature = features.first;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;
    final points =
        coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
    final summary = (feature['properties'] as Map<String, dynamic>)['summary']
        as Map<String, dynamic>;

    return RouteData(
      points: points,
      distanceMeters: (summary['distance'] as num).toDouble(),
      durationSeconds: (summary['duration'] as num).toDouble(),
    );
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
