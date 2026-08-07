import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/search_result.dart';
import 'nearby_locality_cache.dart';
import 'nearby_search_service.dart';
import 'smart_search_engine.dart';

class SearchService {
  static const int _maxHistory = 10;
  static const String _historyKey = 'search_history';

  late final SmartSearchEngine _engine;
  final NearbySearchService _nearbySearch = NearbySearchService();
  Timer? _debounce;
  SharedPreferences? _prefs;

  SearchService({NearbyLocalityCache? localityCache}) {
    _engine = SmartSearchEngine(localityCache: localityCache ?? NearbyLocalityCache());
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<SearchResult>> search(
    String query, {
    double? lat,
    double? lng,
    void Function(List<SearchResult>)? onResults,
  }) {
    return _engine.search(query, lat: lat, lng: lng, onResults: onResults);
  }

  Future<List<SearchResult>> searchByDistance(
    String query, {
    required double lat,
    required double lng,
  }) {
    return _engine.searchByDistance(query, lat: lat, lng: lng);
  }

  Future<List<SearchResult>> searchNearby(
    SearchCategory category, {
    required double lat,
    required double lng,
    double radius = 5000,
  }) {
    return _engine.searchNearby(category, lat: lat, lng: lng, radius: radius);
  }

  /// Category-based nearby search using the 4-tier pipeline.
  /// Automatically expands radius if no results found.
  Future<List<SearchResult>> searchCategoryNearby(
    SearchCategory category, {
    required double lat,
    required double lng,
    String? cityName,
  }) {
    return _nearbySearch.searchCategory(category, lat: lat, lng: lng, cityName: cityName);
  }

  /// Multi-category nearby search (used for Safe Area).
  Future<List<SearchResult>> searchMultipleCategoriesNearby(
    List<SearchCategory> categories, {
    required double lat,
    required double lng,
    String? cityName,
  }) {
    return _nearbySearch.searchMultipleCategories(categories, lat: lat, lng: lng, cityName: cityName);
  }

  /// Smart search that auto-detects category queries and routes to
  /// category-based nearby search instead of text search.
  ///
  /// If the query looks like a generic category ("police", "hospital near me"),
  /// uses Overpass spatial search. Otherwise uses text search.
  Future<List<SearchResult>> searchSmart(
    String query, {
    required double lat,
    required double lng,
    void Function(List<SearchResult>)? onResults,
  }) async {
    final detectedCategory = NearbySearchService.detectCategory(query);
    if (detectedCategory != null) {
      return searchCategoryNearby(detectedCategory, lat: lat, lng: lng);
    }
    return search(query, lat: lat, lng: lng, onResults: onResults);
  }

  /// Debounced smart search that auto-detects category queries.
  void debounceSearchSmart(
    String query, {
    double? lat,
    double? lng,
    required void Function() onLoading,
    required void Function(List<SearchResult>) onResults,
    required void Function(String) onError,
  }) {
    _debounce?.cancel();
    if (query.trim().length < 2) return;

    onLoading();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        bool delivered = false;
        final results = await searchSmart(
          query,
          lat: lat ?? 0,
          lng: lng ?? 0,
          onResults: (progressive) {
            delivered = true;
            onResults(progressive);
          },
        );
        if (!delivered) {
          if (results.isEmpty) {
            onError('No places found');
          } else {
            onResults(results);
          }
        }
      } catch (_) {
        onError('Unable to search places');
      }
    });
  }

  void debounceSearch(
    String query, {
    double? lat,
    double? lng,
    required void Function() onLoading,
    required void Function(List<SearchResult>) onResults,
    required void Function(String) onError,
  }) {
    _debounce?.cancel();
    if (query.trim().length < 2) return;

    onLoading();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        bool delivered = false;
        final results = await search(
          query,
          lat: lat,
          lng: lng,
          onResults: (progressive) {
            delivered = true;
            onResults(progressive);
          },
        );
        if (!delivered) {
          if (results.isEmpty) {
            onError('No places found');
          } else {
            onResults(results);
          }
        }
      } catch (_) {
        onError('Unable to search places');
      }
    });
  }

  Future<List<SearchResult>> getHistory() async {
    final prefs = await _getPrefs();
    final raw = prefs.getStringList(_historyKey) ?? [];
    return raw
        .map((s) => SearchResult.fromMap(json.decode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToHistory(SearchResult result) async {
    final prefs = await _getPrefs();
    final raw = prefs.getStringList(_historyKey) ?? [];
    final items = raw
        .map((s) => SearchResult.fromMap(json.decode(s) as Map<String, dynamic>))
        .toList();

    items.removeWhere((e) =>
        e.position.latitude == result.position.latitude &&
        e.position.longitude == result.position.longitude);

    items.insert(0, result);

    final trimmed = items.take(_maxHistory).toList();
    await prefs.setStringList(
      _historyKey,
      trimmed.map((e) => json.encode(e.toJson())).toList(),
    );
  }

  Future<void> removeHistoryItem(SearchResult result) async {
    final prefs = await _getPrefs();
    final raw = prefs.getStringList(_historyKey) ?? [];
    final items = raw
        .map((s) => SearchResult.fromMap(json.decode(s) as Map<String, dynamic>))
        .toList();

    items.removeWhere((e) =>
        e.position.latitude == result.position.latitude &&
        e.position.longitude == result.position.longitude);

    await prefs.setStringList(
      _historyKey,
      items.map((e) => json.encode(e.toJson())).toList(),
    );
  }

  Future<void> clearHistory() async {
    final prefs = await _getPrefs();
    await prefs.remove(_historyKey);
  }

  void cancelSearch() {
    _debounce?.cancel();
  }

  void dispose() {
    cancelSearch();
  }
}
