import 'dart:async';
import 'dart:collection';
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import 'nearby_locality_cache.dart';
import 'nearby_search_service.dart';
import 'providers/geoapify_provider.dart';
import 'providers/overpass_provider.dart';

class _CacheEntry {
  final List<SearchResult> results;
  final DateTime createdAt;
  _CacheEntry(this.results) : createdAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(minutes: 5);
}

class SmartSearchEngine {
  final GeoapifyProvider _geoapify = GeoapifyProvider();
  final OverpassProvider _overpass = OverpassProvider();
  final NearbyLocalityCache _localityCache;

  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  static const int _maxCacheSize = 20;
  static const double _duplicateThresholdMeters = 50;

  static const Map<String, SearchCategory> _categoryKeywords = {
    'hospital': SearchCategory.hospital,
    'clinic': SearchCategory.hospital,
    'doctor': SearchCategory.hospital,
    'medical': SearchCategory.hospital,
    'pharmacy': SearchCategory.pharmacy,
    'chemist': SearchCategory.pharmacy,
    'police': SearchCategory.police,
    'atm': SearchCategory.atm,
    'bank': SearchCategory.bank,
    'sbi': SearchCategory.bank,
    'restaurant': SearchCategory.restaurant,
    'cafe': SearchCategory.restaurant,
    'food': SearchCategory.restaurant,
    'bus': SearchCategory.busStand,
    'bus station': SearchCategory.busStand,
    'railway': SearchCategory.railwayStation,
    'train': SearchCategory.railwayStation,
    'station': SearchCategory.railwayStation,
    'hotel': SearchCategory.hotel,
    'mall': SearchCategory.mall,
    'market': SearchCategory.mall,
    'shopping': SearchCategory.mall,
    'petrol': SearchCategory.petrolPump,
    'fuel': SearchCategory.petrolPump,
    'park': SearchCategory.park,
    'garden': SearchCategory.park,
    'school': SearchCategory.school,
    'college': SearchCategory.college,
    'university': SearchCategory.university,
    'institute': SearchCategory.university,
  };

  SmartSearchEngine({NearbyLocalityCache? localityCache})
      : _localityCache = localityCache ?? NearbyLocalityCache();

  List<SearchCategory> _expandCategories(String query) {
    final lower = query.toLowerCase().trim();
    final cats = <SearchCategory>{};
    final sorted = _categoryKeywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sorted) {
      final wordPattern = RegExp(r'\b${RegExp.escape(key)}\b');
      if (wordPattern.hasMatch(lower) || key.startsWith(lower)) {
        cats.add(_categoryKeywords[key]!);
      }
    }
    return cats.toList();
  }

  double _dist(LatLng a, LatLng b) => const Distance().distance(a, b);

  int _textMatchTier(String nameLower, String queryLower) {
    if (nameLower == queryLower) return 0;
    if (nameLower.startsWith(queryLower)) return 1;
    if (nameLower.contains(queryLower)) return 2;
    if (queryLower.contains(nameLower)) return 3;
    return 4;
  }

  int _distanceTier(double? distance) {
    if (distance == null) return 5;
    if (distance < 5000) return 0;
    if (distance < 15000) return 1;
    if (distance < 50000) return 2;
    if (distance < 200000) return 3;
    return 4;
  }

  List<SearchResult> _rank(List<SearchResult> results, String query, double? lat, double? lng, {int maxResults = 15}) {
    if (lat != null && lng != null) {
      final user = LatLng(lat, lng);
      results = results.map((r) => r.copyWith(distance: _dist(user, r.position))).toList();
    }

    final lower = query.toLowerCase().trim();
    results.sort((a, b) {
      final aText = _textMatchTier(a.name.toLowerCase(), lower);
      final bText = _textMatchTier(b.name.toLowerCase(), lower);
      if (aText != bText) return aText - bText;

      final aDist = _distanceTier(a.distance);
      final bDist = _distanceTier(b.distance);
      if (aDist != bDist) return aDist - bDist;

      if (a.distance != null && b.distance != null) return a.distance!.compareTo(b.distance!);
      if (a.distance != null) return -1;
      if (b.distance != null) return 1;
      return 0;
    });

    final unique = <SearchResult>[];
    for (final r in results) {
      if (unique.any((e) => _dist(e.position, r.position) < _duplicateThresholdMeters)) continue;
      unique.add(r);
    }

    if (lat != null && lng != null) {
      final hasNearby = unique.any((r) => r.distance != null && r.distance! < 15000);
      if (hasNearby) {
        return unique.where((r) => r.distance == null || r.distance! < 100000).take(maxResults).toList();
      }
    }

    return unique.take(maxResults).toList();
  }

  List<SearchResult> _merge(List<SearchResult> a, List<SearchResult> b) {
    final out = List<SearchResult>.from(a);
    for (final r in b) {
      if (out.any((e) => _dist(e.position, r.position) < _duplicateThresholdMeters)) continue;
      out.add(r);
    }
    return out;
  }

  String _cacheKey(String query, double? lat, double? lng) {
    final n = query.toLowerCase().trim();
    if (lat != null && lng != null) return '$n|${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    return n;
  }

  void _cachePut(String key, List<SearchResult> results) {
    if (_cache.length >= _maxCacheSize) _cache.remove(_cache.keys.first);
    _cache[key] = _CacheEntry(results);
  }

  List<SearchResult>? _cacheGet(String key) {
    final e = _cache[key];
    if (e == null || e.isExpired) { _cache.remove(key); return null; }
    return e.results;
  }

  Future<List<SearchResult>> search(
    String query, {
    double? lat,
    double? lng,
    void Function(List<SearchResult>)? onResults,
  }) async {
    final key = _cacheKey(query, lat, lng);
    final cached = _cacheGet(key);
    if (cached != null) { onResults?.call(cached); return cached; }

    // Auto-detect category queries and redirect to NearbySearchService
    final detectedCategory = NearbySearchService.detectCategory(query);
    if (detectedCategory != null && lat != null && lng != null) {
      final nearbyResults = await NearbySearchService().searchCategory(
        detectedCategory,
        lat: lat,
        lng: lng,
      );
      _cachePut(key, nearbyResults);
      onResults?.call(nearbyResults);
      return nearbyResults;
    }

    // Phase 0: locality cache — instant, no network
    final localMatches = _localityCache.searchLocalities(query);
    if (localMatches.isNotEmpty) {
      onResults?.call(localMatches);
    }

    final categories = _expandCategories(query);

    final geoFuture = _geoapify.search(query, lat: lat, lng: lng);

    final overpassFutures = <Future<List<SearchResult>>>[];
    for (final cat in categories) {
      overpassFutures.add(_overpass.searchNearby(
        lat: lat ?? 0, lng: lng ?? 0, category: cat, radiusMeters: 20000,
      ));
    }

    // Phase 1: deliver Geoapify results
    final geoResults = await geoFuture;
    var earlyMerged = geoResults;
    if (lat != null && lng != null) {
      final cachedPlaces = _localityCache.getNearby(LatLng(lat, lng), 15000);
      earlyMerged = _merge(earlyMerged, cachedPlaces);
    }
    earlyMerged = _merge(earlyMerged, localMatches);
    final earlyRanked = _rank(earlyMerged, query, lat, lng);
    onResults?.call(earlyRanked);

    // Phase 2: merge Overpass results
    final overpassResponses = await Future.wait(overpassFutures, eagerError: false);
    var merged = geoResults;
    for (final r in overpassResponses) {
      merged = _merge(merged, r);
    }

    if (lat != null && lng != null) {
      final cachedPlaces = _localityCache.getNearby(LatLng(lat, lng), 15000);
      merged = _merge(merged, cachedPlaces);
    }
    merged = _merge(merged, localMatches);

    final ranked = _rank(merged, query, lat, lng);
    _cachePut(key, ranked);
    onResults?.call(ranked);
    return ranked;
  }

  Future<List<SearchResult>> searchNearby(
    SearchCategory category, {
    required double lat,
    required double lng,
    double radius = 5000,
  }) async {
    final key = 'nearby_${category.name}_${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    final cached = _cacheGet(key);
    if (cached != null) return cached;

    final results = await NearbySearchService().searchCategory(
      category,
      lat: lat,
      lng: lng,
    );
    _cachePut(key, results);
    return results;
  }

  /// Same as [search] but sorts results purely by distance from user.
  Future<List<SearchResult>> searchByDistance(
    String query, {
    required double lat,
    required double lng,
  }) async {
    final results = await search(query, lat: lat, lng: lng);
    final user = LatLng(lat, lng);
    results.sort((a, b) {
      final da = const Distance().distance(user, a.position);
      final db = const Distance().distance(user, b.position);
      return da.compareTo(db);
    });
    return results;
  }

  void clearCache() => _cache.clear();
}
