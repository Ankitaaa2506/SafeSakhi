import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../models/search_result.dart';

class NearbyLocalityCache {
  final List<SearchResult> _places = [];
  double? _cachedLat;
  double? _cachedLng;
  String? _cachedCity;
  bool _fetching = false;
  final StreamController<List<SearchResult>> _controller =
      StreamController<List<SearchResult>>.broadcast();

  List<SearchResult> get places => List.unmodifiable(_places);
  Stream<List<SearchResult>> get onUpdated => _controller.stream;
  bool get isReady => _places.isNotEmpty;

  static const double _refreshThresholdMeters = 2500;
  static const double _initialRadiusMeters = 10000;

  void updatePosition(double lat, double lng) {
    if (_cachedLat != null && _cachedLng != null) {
      final dist = _haversine(_cachedLat!, _cachedLng!, lat, lng);
      if (dist < _refreshThresholdMeters && _places.isNotEmpty) return;
    }
    final newCity = _cityHint(lat, lng);
    if (_cachedCity != null && newCity == _cachedCity && _places.isNotEmpty) return;

    _fetch(lat, lng);
  }

  void forceRefresh(double lat, double lng) {
    _fetch(lat, lng);
  }

  Future<void> _fetch(double lat, double lng) async {
    if (_fetching) return;
    _fetching = true;

    try {
      final results = await _queryOverpass(lat, lng, _initialRadiusMeters);
      _places
        ..clear()
        ..addAll(results);
      _cachedLat = lat;
      _cachedLng = lng;
      _cachedCity = _cityHint(lat, lng);
      if (!_controller.isClosed) _controller.add(List.unmodifiable(_places));
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  List<SearchResult> searchLocalities(String query) {
    if (_places.isEmpty || query.trim().isEmpty) return [];
    final lower = query.toLowerCase().trim();

    final matches = <SearchResult>[];
    for (final p in _places) {
      final nameLower = p.name.toLowerCase().trim();
      if (nameLower == lower ||
          nameLower.startsWith(lower) ||
          nameLower.contains(lower)) {
        matches.add(p);
      }
    }

    if (_cachedLat != null && _cachedLng != null) {
      final user = LatLng(_cachedLat!, _cachedLng!);
      for (int i = 0; i < matches.length; i++) {
        final d = const Distance().distance(user, matches[i].position);
        matches[i] = matches[i].copyWith(distance: d);
      }
      matches.sort((a, b) => (a.distance ?? 0).compareTo(b.distance ?? 0));
    }

    return matches.take(5).toList();
  }

  List<SearchResult> getNearby(LatLng center, double radiusMeters) {
    final results = <SearchResult>[];
    for (final p in _places) {
      final d = const Distance().distance(center, p.position);
      if (d <= radiusMeters) {
        results.add(p.copyWith(distance: d));
      }
    }
    results.sort((a, b) => (a.distance ?? 0).compareTo(b.distance ?? 0));
    return results;
  }

  Future<List<SearchResult>> _queryOverpass(
      double lat, double lng, double radius) async {
    final query = '''
[out:json][timeout:12];
(
  node["place"="neighbourhood"](around:$radius,$lat,$lng);
  node["place"="suburb"](around:$radius,$lat,$lng);
  node["place"="quarter"](around:$radius,$lat,$lng);
  node["place"="locality"](around:$radius,$lat,$lng);
  node["place"="village"](around:$radius,$lat,$lng);
  node["place"="hamlet"](around:$radius,$lat,$lng);
  node["place"="city_district"](around:$radius,$lat,$lng);
  node["amenity"="university"](around:$radius,$lat,$lng);
  node["amenity"="college"](around:$radius,$lat,$lng);
  node["amenity"="school"](around:$radius,$lat,$lng);
  node["amenity"="hospital"](around:$radius,$lat,$lng);
  node["amenity"="clinic"](around:$radius,$lat,$lng);
  node["amenity"="police"](around:$radius,$lat,$lng);
  node["railway"="station"](around:$radius,$lat,$lng);
  node["amenity"="bus_station"](around:$radius,$lat,$lng);
  node["amenity"="marketplace"](around:$radius,$lat,$lng);
  node["leisure"="park"](around:$radius,$lat,$lng);
  node["tourism"="attraction"](around:$radius,$lat,$lng);
  node["historic"="monument"](around:$radius,$lat,$lng);
  node["historic"="memorial"](around:$radius,$lat,$lng);
  node["amenity"="townhall"](around:$radius,$lat,$lng);
  node["amenity"="community_centre"](around:$radius,$lat,$lng);
  node["landuse"="government"](around:$radius,$lat,$lng);
  node["office"="government"](around:$radius,$lat,$lng);
);
out body;''';

    final response = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return [];

    final data = json.decode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];
    final results = <SearchResult>[];
    final seen = <String>{};

    for (final element in elements) {
      if (element['tags'] == null) continue;
      final tags = element['tags'] as Map<String, dynamic>;
      final name = tags['name'] as String? ??
          tags['name:en'] as String? ??
          tags['name:hi'] as String?;
      if (name == null || name.isEmpty) continue;
      final norm = name.toLowerCase().trim();
      if (seen.contains(norm)) continue;
      seen.add(norm);

      final elLat = (element['lat'] as num?)?.toDouble();
      final elLng = (element['lon'] as num?)?.toDouble();
      if (elLat == null || elLng == null) continue;

      final cat = _tagToCategory(tags);
      if (cat == null) continue;

      results.add(SearchResult(
        id: 'cache_${element['id']}',
        name: name,
        address: '',
        position: LatLng(elLat, elLng),
        category: cat,
        icon: SearchResult.categoryIcon(cat),
      ));
    }

    return results;
  }

  SearchCategory? _tagToCategory(Map<String, dynamic> tags) {
    final place = tags['place'] as String?;
    if (place != null) {
      return switch (place) {
        'neighbourhood' ||
        'suburb' ||
        'quarter' ||
        'locality' ||
        'village' ||
        'hamlet' ||
        'city_district' =>
          SearchCategory.general,
        _ => null,
      };
    }
    final amenity = tags['amenity'] as String?;
    if (amenity != null) {
      return switch (amenity) {
        'university' => SearchCategory.university,
        'college' => SearchCategory.college,
        'school' => SearchCategory.school,
        'hospital' || 'clinic' => SearchCategory.hospital,
        'police' => SearchCategory.police,
        'bus_station' => SearchCategory.busStand,
        'marketplace' => SearchCategory.mall,
        'townhall' || 'community_centre' => SearchCategory.park,
        _ => null,
      };
    }
    if (tags['railway'] == 'station') return SearchCategory.railwayStation;
    if (tags['leisure'] == 'park') return SearchCategory.park;
    if (tags['tourism'] == 'attraction') return SearchCategory.park;
    if (tags['historic'] == 'monument' || tags['historic'] == 'memorial') {
      return SearchCategory.park;
    }
    if (tags['landuse'] == 'government' || tags['office'] == 'government') {
      return SearchCategory.park;
    }
    return null;
  }

  String _cityHint(double lat, double lng) {
    final latStep = (lat * 2).round();
    final lngStep = (lng * 2).round();
    return '${latStep}_$lngStep';
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  void clear() {
    _places.clear();
    _cachedLat = null;
    _cachedLng = null;
    _cachedCity = null;
    if (!_controller.isClosed) _controller.add([]);
  }

  void dispose() {
    _controller.close();
  }
}
