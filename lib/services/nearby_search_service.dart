import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/search_result.dart';
import 'providers/geoapify_provider.dart';
import 'providers/overpass_provider.dart';

class _CacheEntry {
  final List<SearchResult> results;
  final DateTime createdAt;
  _CacheEntry(this.results) : createdAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(minutes: 5);
}

/// Single reusable service for ALL nearby category searches.
///
/// Used by Explore Safe Heaven, SOS Emergency, and Home Screen category chips.
/// Implements a 4-tier search pipeline:
///
/// 1. Geoapify Places API (category filter + circle + proximity bias)
/// 2. Geoapify text search ("police station" / "hospital near me" etc.)
/// 3. Overpass spatial search (OSM amenity tags)
/// 4. Expanded radius Overpass (if still empty)
///
/// Results are merged, deduplicated, sorted by haversine distance,
/// and filtered to remove far-away results when nearby ones exist.
class NearbySearchService {
  static final NearbySearchService _instance = NearbySearchService._();
  factory NearbySearchService() => _instance;
  NearbySearchService._();

  final GeoapifyProvider _geoapify = GeoapifyProvider();
  final OverpassProvider _overpass = OverpassProvider();

  static const double _initialRadius = 15000;
  static const int _maxResults = 20;
  static const double _duplicateThresholdMeters = 50;
  static const double _maxDistanceMeters = 50000;
  static const int _cacheMaxSize = 30;

  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  int _searchCounter = 0;

  // ── Public API ────────────────────────────────────────────────

  /// Search for places of a single category near the given coordinates.
  ///
  /// Returns up to [_maxResults] results sorted by nearest distance.
  /// Implements the full 4-tier pipeline with caching.
  Future<List<SearchResult>> searchCategory(
    SearchCategory category, {
    required double lat,
    required double lng,
    String? cityName,
  }) async {
    _searchCounter++;
    final searchId = _searchCounter;
    final tag = '[SEARCH:$searchId]';

    debugPrint('$tag ═══════════════════════════════════════════');
    debugPrint('$tag SEARCH START: category=${category.name}, lat=$lat, lng=$lng, cityName=$cityName');

    final key = _cacheKey(category, lat, lng);
    debugPrint('$tag CACHE key="$key"');

    final cached = _cacheGet(key);
    if (cached != null) {
      debugPrint('$tag CACHE HIT → returning ${cached.length} cached results');
      debugPrint('$tag ═══════════════════════════════════════════');
      return cached;
    }
    debugPrint('$tag CACHE MISS');

    final userLoc = LatLng(lat, lng);
    final allResults = <SearchResult>[];

    // ── Step 1: Geoapify Places API (category filter + radius) ──
    debugPrint('$tag STEP 1: Geoapify Places category search (radius=${_initialRadius}m)');
    try {
      final categoryResults = await _geoapify.searchNearbyCategory(
        category,
        lat: lat,
        lng: lng,
        radiusMeters: _initialRadius,
        limit: 20,
        searchId: '$searchId-T1',
      );
      debugPrint('$tag STEP 1 RESULT: ${categoryResults.length} results');
      allResults.addAll(categoryResults);
    } catch (e) {
      debugPrint('$tag STEP 1 ERROR: $e');
    }

    // ── Step 2: Geoapify text search with city name ──
    final searchQuery = _searchQueryForCategory(category);
    final query = (cityName != null && cityName.isNotEmpty)
        ? '$searchQuery $cityName'
        : '$searchQuery nearby';
    debugPrint('$tag STEP 2: Geoapify text "$query"');

    try {
      final textResults = await _geoapify.search(
        query,
        lat: lat,
        lng: lng,
        limit: 15,
        searchId: '$searchId-T2',
      );
      debugPrint('$tag STEP 2 RESULT: ${textResults.length} results');
      allResults.addAll(textResults);
    } catch (e) {
      debugPrint('$tag STEP 2 ERROR: $e');
    }

    // ── Step 3: If no results, try Overpass as fallback ──
    if (allResults.isEmpty) {
      debugPrint('$tag STEP 3: Overpass fallback (${_initialRadius}m)');
      try {
        final overpassResults = await _overpass.searchNearby(
          lat: lat,
          lng: lng,
          category: category,
          radiusMeters: _initialRadius,
          searchId: '$searchId-T3',
        );
        debugPrint('$tag STEP 3 RESULT: ${overpassResults.length} results');
        allResults.addAll(overpassResults);
      } catch (e) {
        debugPrint('$tag STEP 3 ERROR: $e');
      }
    } else {
      debugPrint('$tag STEP 3: SKIPPED (have ${allResults.length} results)');
    }

    debugPrint('$tag TOTAL before merge: ${allResults.length}');

    // ── Merge, deduplicate, rank ──
    debugPrint('$tag ═══ MERGE & RANK ═══');
    final ranked = _mergeAndRank(allResults, userLoc, searchId: '$searchId');
    _cachePut(key, ranked);

    debugPrint('$tag ═══ FINAL RESULTS: ${ranked.length} ═══');
    for (int i = 0; i < ranked.length; i++) {
      final r = ranked[i];
      debugPrint('  $tag FINAL[$i]: "${r.name}", dist=${r.distance?.toStringAsFixed(0)}m');
    }
    debugPrint('$tag SEARCH END');
    debugPrint('$tag ═══════════════════════════════════════════');
    return ranked;
  }

  /// Search for places of multiple categories, merge, and sort by distance.
  Future<List<SearchResult>> searchMultipleCategories(
    List<SearchCategory> categories, {
    required double lat,
    required double lng,
    String? cityName,
  }) async {
    final allResults = <SearchResult>[];
    final userLoc = LatLng(lat, lng);

    for (final category in categories) {
      final results = await searchCategory(
        category,
        lat: lat,
        lng: lng,
        cityName: cityName,
      );
      allResults.addAll(results);
    }

    return _mergeAndRank(allResults, userLoc);
  }

  // ── Result processing ──────────────────────────────────────────

  /// Merge results from multiple providers, deduplicate, compute
  /// haversine distance, sort by nearest, and apply proximity filter.
  List<SearchResult> _mergeAndRank(List<SearchResult> raw, LatLng userLoc, {String? searchId}) {
    final tag = searchId != null ? '[SEARCH:$searchId]' : '';
    debugPrint('$tag MERGE INPUT: ${raw.length} raw results');

    // 1. Compute haversine distance for every result
    final withDistance = raw.map((r) {
      final dist = const Distance().distance(userLoc, r.position);
      return r.copyWith(distance: dist);
    }).toList();

    for (int i = 0; i < withDistance.length; i++) {
      final r = withDistance[i];
      debugPrint('  $tag RAW[$i]: "${r.name}", cat=${r.category.name}, haversine=${r.distance?.toStringAsFixed(0)}m, lat=${r.position.latitude}, lng=${r.position.longitude}');
    }

    // 2. Deduplicate by coordinates (within 50m) OR identical name+address
    final unique = <SearchResult>[];
    int dedupeCount = 0;
    for (final r in withDistance) {
      final isDuplicate = unique.any((e) {
        final coordDist = const Distance().distance(e.position, r.position);
        if (coordDist < _duplicateThresholdMeters) return true;
        if (e.name.toLowerCase() == r.name.toLowerCase() &&
            e.address.toLowerCase() == r.address.toLowerCase() &&
            e.address.isNotEmpty) {
          return true;
        }
        return false;
      });
      if (isDuplicate) {
        dedupeCount++;
        debugPrint('  $tag DEDUP: "${r.name}" (duplicate of existing)');
      } else {
        unique.add(r);
      }
    }
    debugPrint('$tag AFTER DEDUP: ${unique.length} unique (removed $dedupeCount duplicates)');

    // 3. Sort strictly by nearest distance
    unique.sort((a, b) => (a.distance ?? 0).compareTo(b.distance ?? 0));
    debugPrint('$tag AFTER SORT: nearest=${unique.isNotEmpty ? unique.first.distance?.toStringAsFixed(0) : "N/A"}m, farthest=${unique.isNotEmpty ? unique.last.distance?.toStringAsFixed(0) : "N/A"}m');

    // 4. Proximity filter: if any result within 15km, remove results > 100km
    final hasNearby = unique.any((r) => r.distance != null && r.distance! < 15000);
    debugPrint('$tag PROXIMITY FILTER: hasNearby(within15km)=$hasNearby');
    if (hasNearby) {
      final beforeCount = unique.length;
      final filtered = unique
          .where((r) => r.distance == null || r.distance! < 100000)
          .take(_maxResults)
          .toList();
      debugPrint('$tag PROXIMITY FILTER: removed ${beforeCount - filtered.length} results >100km, kept ${filtered.length}');
      return filtered;
    }

    final beforeCapCount = unique.length;
    final capped = unique
        .where((r) => r.distance == null || r.distance! <= _maxDistanceMeters)
        .take(_maxResults)
        .toList();
    debugPrint('$tag DISTANCE CAP: removed ${beforeCapCount - capped.length} results >${(_maxDistanceMeters / 1000).round()}km, kept ${capped.length}');
    return capped;
  }

  // ── Cache ─────────────────────────────────────────────────────

  String _searchQueryForCategory(SearchCategory category) {
    return switch (category) {
      SearchCategory.safeArea => 'park',
      SearchCategory.womenHelp => 'women helpline',
      SearchCategory.police => 'police station',
      SearchCategory.hospital => 'hospital',
      SearchCategory.pharmacy => 'pharmacy',
      SearchCategory.fireStation => 'fire station',
      SearchCategory.atm => 'ATM',
      SearchCategory.restaurant => 'restaurant',
      SearchCategory.cafe => 'cafe',
      SearchCategory.mall => 'shopping mall',
      SearchCategory.petrolPump => 'petrol pump',
      SearchCategory.busStand => 'bus stand',
      SearchCategory.railwayStation => 'railway station',
      SearchCategory.school => 'school',
      SearchCategory.college => 'college',
      SearchCategory.university => 'university',
      SearchCategory.bank => 'bank',
      SearchCategory.hotel => 'hotel',
      SearchCategory.park => 'park',
      SearchCategory.general => 'place',
    };
  }

  String _cacheKey(SearchCategory category, double lat, double lng) {
    return '${category.name}|${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
  }

  void _cachePut(String key, List<SearchResult> results) {
    if (_cache.length >= _cacheMaxSize) _cache.remove(_cache.keys.first);
    _cache[key] = _CacheEntry(results);
  }

  List<SearchResult>? _cacheGet(String key) {
    final e = _cache[key];
    if (e == null || e.isExpired) {
      _cache.remove(key);
      return null;
    }
    return e.results;
  }

  void clearCache() => _cache.clear();

  // ── Category detection (for SmartSearchEngine integration) ───

  /// Check if a search query looks like a generic category name
  /// (e.g., "police", "hospital near me", "pharmacy").
  ///
  /// Returns the matching [SearchCategory] or null if it's a specific place name.
  static SearchCategory? detectCategory(String query) {
    final lower = query.toLowerCase().trim();

    // Remove common filler phrases
    final cleaned = lower
        .replaceAll(RegExp(r'\bnear\s*me\b'), '')
        .replaceAll(RegExp(r'\bnearby\b'), '')
        .replaceAll(RegExp(r'\bnearest\b'), '')
        .replaceAll(RegExp(r'\baround\b'), '')
        .replaceAll(RegExp(r'\bin\s*my\s*area\b'), '')
        .trim();

    // Exact or near-exact category matches
    const categoryPatterns = {
      SearchCategory.police: [
        'police',
        'police station',
        'thana',
        'police chowki',
      ],
      SearchCategory.hospital: [
        'hospital',
        'clinic',
        'medical center',
        'medical centre',
        'health center',
        'health centre',
        'nursing home',
        'healthcare',
      ],
      SearchCategory.pharmacy: [
        'pharmacy',
        'chemist',
        'medical store',
        'medicine shop',
        'drug store',
        'druggist',
      ],
      SearchCategory.safeArea: [
        'safe area',
        'safe zone',
        'safe place',
        'safety',
      ],
      SearchCategory.womenHelp: [
        'women help',
        'women safety',
        'women support',
        'mahila',
        'women helpline',
      ],
    };

    for (final entry in categoryPatterns.entries) {
      for (final pattern in entry.value) {
        if (cleaned == pattern) {
          return entry.key;
        }
      }
    }

    return null;
  }
}
