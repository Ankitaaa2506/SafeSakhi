import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/api_keys.dart';
import '../../models/search_result.dart';

class GeoapifyProvider {
  static const String _baseUrl = 'https://api.geoapify.com/v1/geocode/autocomplete';
  static const String _placesUrl = 'https://api.geoapify.com/v2/places';
  static const Duration _timeout = Duration(seconds: 8);

  static const Map<SearchCategory, String> _categoryFilter = {
    SearchCategory.hospital: 'amenity.hospital,amenity.clinic,amenity.doctors',
    SearchCategory.police: 'amenity.police',
    SearchCategory.pharmacy: 'amenity.pharmacy',
    SearchCategory.fireStation: 'amenity.fire_station',
    SearchCategory.atm: 'amenity.atm,amenity.bank',
    SearchCategory.restaurant: 'amenity.restaurant,amenity.fast_food',
    SearchCategory.cafe: 'amenity.cafe,amenity.bar',
    SearchCategory.mall: 'shop mall,shop.supermarket',
    SearchCategory.petrolPump: 'amenity.fuel',
    SearchCategory.busStand: 'amenity.bus_station',
    SearchCategory.railwayStation: 'railway.station',
    SearchCategory.school: 'amenity.school',
    SearchCategory.college: 'amenity.college',
    SearchCategory.university: 'amenity.university',
    SearchCategory.bank: 'amenity.bank',
    SearchCategory.hotel: 'tourism.hotel,tourism.hostel',
    SearchCategory.park: 'leisure.park',
    SearchCategory.safeArea: 'leisure.park,leisure.playground',
    SearchCategory.womenHelp: 'amenity.social_facility',
  };

  /// Text autocomplete search.
  Future<List<SearchResult>> search(
    String query, {
    double? lat,
    double? lng,
    String? filter,
    int limit = 10,
    String? searchId,
  }) async {
    final params = <String, String>{
      'text': query,
      'apiKey': ApiKeys.geoapify,
      'limit': limit.toString(),
      'filter': 'countrycode:in',
    };
    if (lat != null && lng != null) {
      params['bias'] = 'proximity:$lng,$lat';
    }
    if (filter != null && filter.isNotEmpty) {
      params['filter'] = 'countrycode:in,$filter';
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → Request URL: $uri');
    debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → lat=$lat, lng=$lng, query="$query"');

    try {
      final response = await http.get(uri).timeout(_timeout);
      debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → HTTP ${response.statusCode}');
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → Raw features count: ${features.length}');

      final results = <SearchResult>[];
      for (int i = 0; i < features.length; i++) {
        final f = features[i] as Map<String, dynamic>;
        final sr = SearchResult.fromGeoapify(f);
        final props = f['properties'] as Map<String, dynamic>?;
        final categories = props?['categories'] ?? props?['datasource']?['sourcetags'] ?? [];
        debugPrint(
          '  [SEARCH:$searchId] GEOAPIFY TEXT Result[$i]: '
          'name="${sr.name}", lat=${sr.position.latitude}, lng=${sr.position.longitude}, '
          'categories=$categories, address="${sr.address.length > 60 ? sr.address.substring(0, 60) : sr.address}"',
        );
        results.add(sr);
      }
      debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → Parsed ${results.length} SearchResults');
      return results;
    } catch (e) {
      debugPrint('[SEARCH:$searchId] GEOAPIFY TEXT → ERROR: $e');
      return [];
    }
  }

  /// Category-based nearby search using Geoapify Places API.
  ///
  /// Searches within a circle of [radiusMeters] around (lat, lng).
  /// Uses the v2/places endpoint with category filters.
  Future<List<SearchResult>> searchNearbyCategory(
    SearchCategory category, {
    required double lat,
    required double lng,
    double radiusMeters = 15000,
    int limit = 20,
    String? searchId,
  }) async {
    final categoryFilter = _categoryFilter[category];
    if (categoryFilter == null) {
      debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → No filter for category ${category.name}');
      return [];
    }

    final params = <String, String>{
      'categories': categoryFilter,
      'filter': 'circle:$lng,$lat,$radiusMeters',
      'bias': 'proximity:$lng,$lat',
      'limit': limit.toString(),
      'apiKey': ApiKeys.geoapify,
    };

    final uri = Uri.parse(_placesUrl).replace(queryParameters: params);
    debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → Request URL: $uri');
    debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → lat=$lat, lng=$lng, radius=${radiusMeters}m, category=${category.name}, filter="$categoryFilter"');

    try {
      final response = await http.get(uri).timeout(_timeout);
      debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → HTTP ${response.statusCode}');
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → Raw features count: ${features.length}');

      final results = <SearchResult>[];
      for (int i = 0; i < features.length; i++) {
        final f = features[i] as Map<String, dynamic>;
        final sr = SearchResult.fromGeoapify(f);
        final props = f['properties'] as Map<String, dynamic>?;
        final categories = props?['categories'] ?? [];
        debugPrint(
          '  [SEARCH:$searchId] GEOAPIFY PLACES Result[$i]: '
          'name="${sr.name}", lat=${sr.position.latitude}, lng=${sr.position.longitude}, '
          'categories=$categories',
        );
        results.add(sr);
      }
      debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → Parsed ${results.length} SearchResults');
      return results;
    } catch (e) {
      debugPrint('[SEARCH:$searchId] GEOAPIFY PLACES → ERROR: $e');
      return [];
    }
  }
}
