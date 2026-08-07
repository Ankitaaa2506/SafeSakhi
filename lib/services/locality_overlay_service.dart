import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import 'nearby_locality_cache.dart';

class OverlayPlace {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final OverlayCategory category;
  final int priority;
  final double distanceFromCenter;

  const OverlayPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    required this.priority,
    this.distanceFromCenter = 0,
  });
}

enum OverlayCategory {
  neighbourhood,
  suburb,
  quarter,
  locality,
  village,
  university,
  college,
  school,
  hospital,
  railwayStation,
  busStation,
  government,
  park,
  market,
  landmark,
}

class LocalityOverlayService {
  final NearbyLocalityCache _cache;
  StreamSubscription<List<SearchResult>>? _subscription;

  double _lastZoom = 14.0;
  double _lastLat = 0;
  double _lastLng = 0;
  void Function(List<OverlayPlace>)? _lastOnUpdate;
  List<OverlayPlace> _currentPlaces = [];

  List<OverlayPlace> get currentPlaces => _currentPlaces;

  static const Set<String> _baseMapLabels = {
    'barari',
    'sabour',
    'tilkamanjhi',
    'nathnagar',
    'mayaganj',
    'zero mile',
    'khanjarpur',
    'laheriasarai',
    'dalsinghsarai',
    'bhatta',
    'khalifabagh',
    'tamta',
    'ajjmnichak',
    'gopalpur',
    'kamargola',
    'adampur',
    'chandni chowk',
    'gandhi maidan',
    'patna city',
    'banka',
    'katihar',
    'purnia',
    'munger',
  };

  // Keep labels visible within 6km, hide beyond
  static const double _maxVisibleDistanceMeters = 6000;

  // At very high zoom, base map labels appear — hide less important first
  static const Map<OverlayCategory, double> _hideAtZoom = {
    OverlayCategory.village: 14.0,
    OverlayCategory.quarter: 14.0,
    OverlayCategory.market: 14.0,
    OverlayCategory.landmark: 14.0,
    OverlayCategory.park: 14.0,
    OverlayCategory.school: 14.5,
    OverlayCategory.suburb: 14.5,
    OverlayCategory.locality: 14.5,
    OverlayCategory.neighbourhood: 14.5,
    OverlayCategory.busStation: 15.0,
    OverlayCategory.college: 15.0,
    OverlayCategory.government: 15.0,
    OverlayCategory.university: 16.0,
    OverlayCategory.railwayStation: 16.0,
    OverlayCategory.hospital: 16.0,
  };

  LocalityOverlayService({NearbyLocalityCache? cache})
      : _cache = cache ?? NearbyLocalityCache() {
    _subscription = _cache.onUpdated.listen((_) {
      if (_lastOnUpdate != null) _refresh();
    });
  }

  void onCameraChanged({
    required double lat,
    required double lng,
    required double zoom,
    required void Function(List<OverlayPlace>) onUpdate,
  }) {
    _lastZoom = zoom;
    _lastLat = lat;
    _lastLng = lng;
    _lastOnUpdate = onUpdate;
    _refresh();
  }

  void _refresh() {
    final center = LatLng(_lastLat, _lastLng);
    final radius = _radiusForZoom(_lastZoom);
    final results = _cache.getNearby(center, radius);
    final distance = const Distance();

    final places = results.map((r) {
      final dist = distance(center, r.position);
      return OverlayPlace(
        id: r.id,
        name: r.name,
        lat: r.position.latitude,
        lng: r.position.longitude,
        category: _categoryFromResult(r),
        priority: _priorityFromResult(r),
        distanceFromCenter: dist,
      );
    }).toList();

    _currentPlaces = _applyGradualFilter(places, _lastZoom);
    _currentPlaces = _removeDuplicateLabels(_currentPlaces);
    _lastOnUpdate?.call(_currentPlaces);
  }

  OverlayCategory _categoryFromResult(SearchResult r) {
    return switch (r.category) {
      SearchCategory.university => OverlayCategory.university,
      SearchCategory.college => OverlayCategory.college,
      SearchCategory.school => OverlayCategory.school,
      SearchCategory.hospital => OverlayCategory.hospital,
      SearchCategory.railwayStation => OverlayCategory.railwayStation,
      SearchCategory.busStand => OverlayCategory.busStation,
      SearchCategory.mall => OverlayCategory.market,
      SearchCategory.park => OverlayCategory.park,
      SearchCategory.police => OverlayCategory.government,
      _ => OverlayCategory.locality,
    };
  }

  int _priorityFromResult(SearchResult r) {
    return switch (r.category) {
      SearchCategory.university => 100,
      SearchCategory.railwayStation => 70,
      SearchCategory.hospital => 75,
      SearchCategory.college => 80,
      SearchCategory.busStand => 65,
      SearchCategory.mall => 60,
      SearchCategory.park => 50,
      SearchCategory.police => 55,
      _ => 90,
    };
  }

  List<OverlayPlace> _applyGradualFilter(List<OverlayPlace> places, double zoom) {
    // Primary filter: remove places beyond 6km from center
    final withinRange = <OverlayPlace>[];
    for (final place in places) {
      if (place.distanceFromCenter <= _maxVisibleDistanceMeters) {
        withinRange.add(place);
      }
    }

    // Secondary filter: at very high zoom, hide less important categories
    // even within range (base map labels start appearing)
    final visible = <OverlayPlace>[];
    for (final place in withinRange) {
      final hideZoom = _hideAtZoom[place.category] ?? 16.0;
      if (zoom >= hideZoom) continue;
      visible.add(place);
    }

    visible.sort((a, b) => a.priority.compareTo(b.priority));

    final maxLabels = _maxLabelsForZoom(zoom);
    if (visible.length > maxLabels) {
      return visible.sublist(0, maxLabels);
    }
    return visible;
  }

  List<OverlayPlace> _removeDuplicateLabels(List<OverlayPlace> places) {
    return places.where((p) {
      final norm = p.name.toLowerCase().trim();
      return !_baseMapLabels.contains(norm);
    }).toList();
  }

  int _maxLabelsForZoom(double zoom) {
    if (zoom >= 17) return 15;
    if (zoom >= 15.5) return 20;
    if (zoom >= 14) return 25;
    if (zoom >= 12) return 30;
    if (zoom >= 10) return 30;
    if (zoom >= 8) return 25;
    if (zoom >= 6) return 15;
    return 8;
  }

  double _radiusForZoom(double zoom) {
    if (zoom >= 16) return 7000;
    if (zoom >= 14) return 8000;
    if (zoom >= 12) return 10000;
    if (zoom >= 10) return 15000;
    if (zoom >= 8) return 25000;
    return 40000;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
