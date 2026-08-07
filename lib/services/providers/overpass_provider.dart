import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../../models/search_result.dart';

class OverpassProvider {
  static const String _baseUrl = 'https://overpass-api.de/api/interpreter';
  static const Duration _timeout = Duration(seconds: 10);

  static const Map<SearchCategory, List<String>> _categoryTags = {
    SearchCategory.hospital: ['hospital', 'clinic', 'doctors', 'medical_center'],
    SearchCategory.police: ['police'],
    SearchCategory.pharmacy: ['pharmacy'],
    SearchCategory.fireStation: ['fire_station'],
    SearchCategory.atm: ['atm', 'bank'],
    SearchCategory.restaurant: ['restaurant', 'fast_food', 'food_court', 'cafe'],
    SearchCategory.cafe: ['cafe', 'bar'],
    SearchCategory.mall: ['mall', 'supermarket', 'marketplace'],
    SearchCategory.petrolPump: ['fuel'],
    SearchCategory.busStand: ['bus_station'],
    SearchCategory.railwayStation: ['railway_station'],
    SearchCategory.school: ['school'],
    SearchCategory.college: ['college'],
    SearchCategory.university: ['university'],
    SearchCategory.bank: ['bank'],
    SearchCategory.hotel: ['hotel', 'motel', 'hostel', 'guest_house'],
    SearchCategory.park: ['park', 'playground'],
    SearchCategory.safeArea: ['park', 'playground', 'townhall', 'community_centre'],
    SearchCategory.womenHelp: ['social_facility', 'community_centre'],
  };

  static const Map<SearchCategory, String> _categoryTagKey = {
    SearchCategory.park: 'leisure',
    SearchCategory.safeArea: 'leisure',
    SearchCategory.hotel: 'tourism',
    SearchCategory.fireStation: 'emergency',
    SearchCategory.mall: 'shop',
  };

  String _buildRadiusQuery({
    required double lat,
    required double lng,
    required SearchCategory category,
    required double radiusMeters,
  }) {
    final tags = _categoryTags[category] ?? [];
    final tagKey = _categoryTagKey[category] ?? 'amenity';
    final tagFilters = tags
        .map((tag) => 'node["$tagKey"="$tag"](around:$radiusMeters,$lat,$lng);'
            'way["$tagKey"="$tag"](around:$radiusMeters,$lat,$lng);')
        .join('\n  ');

    return '''
[out:json][timeout:10];
(
  $tagFilters
);
out center tags;''';
  }

  String _buildAreaQuery({
    required double south,
    required double north,
    required double west,
    required double east,
    required SearchCategory category,
  }) {
    final tags = _categoryTags[category] ?? [];
    final tagKey = _categoryTagKey[category] ?? 'amenity';
    final tagFilters = tags
        .map((tag) => 'node["$tagKey"="$tag"]($south,$west,$north,$east);'
            'way["$tagKey"="$tag"]($south,$west,$north,$east);')
        .join('\n  ');

    return '''
[out:json][timeout:15];
(
  $tagFilters
);
out center tags;''';
  }

  Future<List<SearchResult>> searchNearby({
    required double lat,
    required double lng,
    required SearchCategory category,
    double radiusMeters = 5000,
    String? searchId,
  }) async {
    final query = _buildRadiusQuery(
      lat: lat,
      lng: lng,
      category: category,
      radiusMeters: radiusMeters,
    );
    debugPrint('[SEARCH:$searchId] OVERPASS → searchNearby: lat=$lat, lng=$lng, radius=${radiusMeters}m, category=${category.name}');
    return _executeQuery(query, category, searchId: searchId);
  }

  Future<List<SearchResult>> searchLocalities({
    required double lat,
    required double lng,
    double radiusMeters = 10000,
  }) async {
    final query = '''
[out:json][timeout:10];
(
  node["place"="neighbourhood"](around:$radiusMeters,$lat,$lng);
  node["place"="suburb"](around:$radiusMeters,$lat,$lng);
  node["place"="quarter"](around:$radiusMeters,$lat,$lng);
  node["place"="locality"](around:$radiusMeters,$lat,$lng);
  node["place"="village"](around:$radiusMeters,$lat,$lng);
  node["place"="hamlet"](around:$radiusMeters,$lat,$lng);
  node["place"="city_district"](around:$radiusMeters,$lat,$lng);
);
out body;''';

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            body: {'data': query},
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      return elements
          .where((e) => e['tags'] != null && (e['tags'] as Map).isNotEmpty)
          .map((e) {
            final tags = e['tags'] as Map<String, dynamic>;
            final name = tags['name'] as String? ??
                tags['name:en'] as String? ??
                tags['name:hi'] as String? ??
                '';
            final latV = (e['lat'] as num?)?.toDouble() ?? 0;
            final lon = (e['lon'] as num?)?.toDouble() ?? 0;
            return SearchResult(
              id: 'osm_${e['id']}',
              name: name,
              address: '',
              position: LatLng(latV, lon),
              category: SearchCategory.general,
              icon: '📍',
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<SearchResult>> searchInArea({
    required double south,
    required double north,
    required double west,
    required double east,
    required SearchCategory category,
  }) async {
    final query = _buildAreaQuery(
      south: south,
      north: north,
      west: west,
      east: east,
      category: category,
    );

    return _executeQuery(query, category);
  }

  Future<List<SearchResult>> _executeQuery(
    String query,
    SearchCategory category, {
    String? searchId,
  }) async {
    debugPrint('[SEARCH:$searchId] OVERPASS → Query:\n$query');
    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            body: {'data': query},
            headers: {'User-Agent': 'SafeSakhi/1.0 (Flutter)'},
          )
          .timeout(_timeout);

      debugPrint('[SEARCH:$searchId] OVERPASS → HTTP ${response.statusCode}');
      if (response.statusCode == 406) {
        debugPrint('[SEARCH:$searchId] OVERPASS → Retrying without body encoding...');
        final retryResponse = await http
            .post(
              Uri.parse('$_baseUrl?data=${Uri.encodeComponent(query)}'),
              headers: {'User-Agent': 'SafeSakhi/1.0 (Flutter)'},
            )
            .timeout(_timeout);
        debugPrint('[SEARCH:$searchId] OVERPASS → Retry HTTP ${retryResponse.statusCode}');
        if (retryResponse.statusCode != 200) return [];
        final data = json.decode(retryResponse.body) as Map<String, dynamic>;
        final elements = data['elements'] as List<dynamic>? ?? [];
        debugPrint('[SEARCH:$searchId] OVERPASS → Retry raw elements: ${elements.length}');
        final results = <SearchResult>[];
        for (int i = 0; i < elements.length; i++) {
          final e = elements[i] as Map<String, dynamic>;
          final sr = SearchResult.fromOverpass(element: e, category: category);
          if (sr == null) continue;
          final tags = e['tags'] as Map<String, dynamic>? ?? {};
          debugPrint('  [SEARCH:$searchId] OVERPASS RETRY Result[$i]: name="${sr.name}", lat=${sr.position.latitude}, lng=${sr.position.longitude}, amenity=${tags['amenity']}');
          results.add(sr);
        }
        return results;
      }
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];
      debugPrint('[SEARCH:$searchId] OVERPASS → Raw elements count: ${elements.length}');

      final results = <SearchResult>[];
      for (int i = 0; i < elements.length; i++) {
        final e = elements[i] as Map<String, dynamic>;
        final sr = SearchResult.fromOverpass(element: e, category: category);
        if (sr == null) {
          debugPrint('  [SEARCH:$searchId] OVERPASS Result[$i]: SKIPPED (no coordinates)');
          continue;
        }
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        debugPrint(
          '  [SEARCH:$searchId] OVERPASS Result[$i]: '
          'name="${sr.name}", lat=${sr.position.latitude}, lng=${sr.position.longitude}, '
          'amenity=${tags['amenity']}, category=${category.name}',
        );
        results.add(sr);
      }
      debugPrint('[SEARCH:$searchId] OVERPASS → Parsed ${results.length} SearchResults (from ${elements.length} elements)');
      return results;
    } catch (e) {
      debugPrint('[SEARCH:$searchId] OVERPASS → ERROR: $e');
      return [];
    }
  }
}
