import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/search_bar.dart';
import '../widgets/location_button.dart';
import '../widgets/search_results_overlay.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/road_bottom_sheet.dart';
import '../widgets/overlays/map_overlays.dart';
import '../widgets/quick_action_list_sheet.dart';
import '../theme/constants.dart';
import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/firestore_service.dart';
import '../services/search_service.dart';
import '../services/nearby_search_service.dart';
import '../services/nearby_locality_cache.dart';
import '../services/locality_overlay_service.dart';
import '../config/api_keys.dart';
import '../config/map_layers.dart';
import '../models/search_result.dart';
import '../providers/auth_provider.dart';
import '../screens/review_form_screen.dart';
import '../screens/community_reviews_screen.dart';
import '../screens/route_selection_screen.dart';
import '../services/safety_report_share.dart';
import '../widgets/auth_popup.dart';

class HomeScreen extends StatefulWidget {
  final SearchCategory? onCategoryFromDashboard;
  const HomeScreen({super.key, this.onCategoryFromDashboard});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final LocationService _locationService = LocationService();
  final MapService _mapService = MapService();
  final NearbyLocalityCache _localityCache = NearbyLocalityCache();
  late final SearchService _searchService;
  late final LocalityOverlayService _overlayService;
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  final Completer<MapLibreMapController> _mapController = Completer<MapLibreMapController>();
  MapLibreMapController? _mapCtrl;

  LatLng? _currentPosition;
  bool _isLocating = false;
  bool _isFollowingLocation = false;
  double? _currentAccuracy;
  StreamSubscription<Position>? _positionSubscription;

  bool _searchFocused = false;
  SearchPanelState _panelState = SearchPanelState.history;
  List<SearchResult> _searchResults = [];
  List<SearchResult> _searchHistory = [];
  String? _searchError;
  SearchResult? _highlightedResult;

  double _currentZoom = 14.0;
  double _currentBearing = 0.0;

  late final AnimationController _fabAnimController;
  late final Animation<double> _fabFade;
  late final AnimationController _panelAnimController;
  late final Animation<double> _panelFade;
  late final Animation<Offset> _panelSlide;

  bool _overlayLayerReady = false;
  bool _programmaticTextChange = false;
  bool _selectedMarkerReady = false;
  bool _nearbyMarkersReady = false;
  Timer? _overlayDebounce;
  Timer? _saveCameraDebounce;

  // Category quick action state
  SearchCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();

    _searchService = SearchService(localityCache: _localityCache);
    _overlayService = LocalityOverlayService(cache: _localityCache);

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _fabFade = CurvedAnimation(parent: _fabAnimController, curve: Curves.easeInOut);

    _panelAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelFade = CurvedAnimation(parent: _panelAnimController, curve: Curves.easeOut);
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _panelAnimController, curve: Curves.easeOutCubic));

    _searchFocusNode.addListener(_onFocusChange);
    _searchController.addListener(_onTextChanged);

    if (widget.onCategoryFromDashboard != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) selectCategory(widget.onCategoryFromDashboard!);
        });
      });
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    if (!_mapController.isCompleted) {
      _mapController.complete(controller);
    }
    _mapCtrl = controller;

    controller.addListener(() {
      final pos = controller.cameraPosition;
      if (pos != null && mounted) {
        setState(() {
          _currentZoom = pos.zoom;
          _currentBearing = pos.bearing;
        });
        if (_searchResults.isEmpty && _highlightedResult == null) {
          _overlayDebounce?.cancel();
          _overlayDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted && _searchResults.isEmpty && _highlightedResult == null) {
              _overlayService.onCameraChanged(
                lat: pos.target.latitude,
                lng: pos.target.longitude,
                zoom: pos.zoom,
                onUpdate: (places) {
                  if (mounted) _updateOverlay(places);
                },
              );
            }
          });
        }
        _saveCameraDebounce?.cancel();
        _saveCameraDebounce = Timer(const Duration(milliseconds: 1000), () {
          _mapService.saveCameraState(
            latlong2.LatLng(pos.target.latitude, pos.target.longitude),
            pos.zoom,
            pos.bearing,
          );
        });
      }
    });
  }

  void _onStyleLoaded() {
    _enhanceMapLabels();
    _initBackground();
    final controller = _mapCtrl;
    if (controller != null) {
      MapLayerConfig.validateLayers(controller);
    }
    if (_currentPosition == null) {
      _onCurrentLocationPressed();
    }
  }

  Future<void> _enhanceMapLabels() async {
    final controller = _mapCtrl;
    if (controller == null) return;

    // NOTE: We intentionally skip modifying existing MapTiler label layers.
    // setLayerProperties with SymbolLayerProperties sends null for unspecified
    // fields, which resets text rendering on the base layers, hiding all
    // default labels (roads, places, landmarks). Default labels are now
    // preserved as-is; only our custom layers are added below.

    try {
      final sourceIds = await controller.getSourceIds();
      for (final sourceId in sourceIds) {
        try {
          await controller.addSymbolLayer(
            sourceId,
            'dynamic-edu-labels',
            SymbolLayerProperties(
              textField: ['get', 'name'],
              textSize: [
                'interpolate', ['linear'], ['zoom'],
                10, 9,
                14, 11,
                18, 13,
              ],
              textColor: '#D32F2F',
              textFont: ['DIN Pro Medium', 'Arial Unicode MS Regular'],
              textOffset: [0, 1.5],
              textAnchor: 'top',
              textAllowOverlap: true,
              textIgnorePlacement: true,
              textHaloColor: '#FFFFFF',
              textHaloWidth: 1.5,
              symbolSortKey: 1,
              symbolSpacing: 80,
            ),
            sourceLayer: 'poi',
            minzoom: 10,
            maxzoom: 22,
            filter: [
              'any',
              ['==', ['get', 'class'], 'college'],
              ['==', ['get', 'class'], 'university'],
              ['==', ['get', 'class'], 'school'],
            ],
          );
          break;
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _initBackground() async {
    final controller = _mapCtrl;
    if (controller == null) return;

    final cached = _locationService.lastPosition;

    if (cached != null) {
      final latLng = LatLng(cached.latitude, cached.longitude);
      setState(() {
        _currentPosition = latLng;
        _currentAccuracy = cached.accuracy;
      });
      _localityCache.updatePosition(latLng.latitude, latLng.longitude);

      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(latLng, 14.0),
      );

      await _initUserLocationLayer();

      _overlayService.onCameraChanged(
        lat: latLng.latitude,
        lng: latLng.longitude,
        zoom: _currentZoom,
        onUpdate: (places) {
          if (mounted) _updateOverlay(places);
        },
      );
    } else {
      final saved = await _mapService.restoreCameraState();
      if (saved != null && mounted) {
        await controller.moveCamera(
          CameraUpdate.newLatLngZoom(
              LatLng(saved.center.latitude, saved.center.longitude), saved.zoom),
        );
      }
    }

    _locationService.startBackgroundStream();

    _positionSubscription?.cancel();
    _positionSubscription = _locationService.onPositionChanged.listen((position) {
      if (!mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = latLng;
        _currentAccuracy = position.accuracy;
      });
      _localityCache.updatePosition(latLng.latitude, latLng.longitude);
      _updateUserLocationPosition();
    });

    if (cached == null) {
      if (!mounted) return;
      setState(() => _isLocating = true);
      _locationService.getCurrentLocation().then((position) async {
        if (!mounted) return;
        setState(() => _isLocating = false);

        if (position != null) {
          final latLng = LatLng(position.latitude, position.longitude);
          setState(() {
            _currentPosition = latLng;
            _currentAccuracy = position.accuracy;
          });

          _localityCache.updatePosition(latLng.latitude, latLng.longitude);

          await _initUserLocationLayer();

          if (mounted) {
            await controller.animateCamera(
              CameraUpdate.newLatLngZoom(latLng, 14.0),
              duration: const Duration(milliseconds: 700),
            );
          }

          _overlayService.onCameraChanged(
            lat: latLng.latitude,
            lng: latLng.longitude,
            zoom: _currentZoom,
            onUpdate: (places) {
              if (mounted) _updateOverlay(places);
            },
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied. Tap the location button to retry.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _overlayDebounce?.cancel();
    _saveCameraDebounce?.cancel();
    _positionSubscription?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchController.removeListener(_onTextChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _fabAnimController.dispose();
    _panelAnimController.dispose();
    _locationService.dispose();
    _searchService.dispose();
    _overlayService.dispose();
    _localityCache.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _searchFocusNode.hasFocus;
    setState(() => _searchFocused = focused);
    if (focused) {
      // Clear category selection when search is focused
      if (_selectedCategory != null) {
        _clearCategoryState();
      }
      _fabAnimController.reverse();
      _panelAnimController.forward(from: 0);
      _loadHistory();
      setState(() => _panelState = SearchPanelState.history);
    } else {
      _fabAnimController.forward();
      _panelAnimController.reverse();
    }
  }

  void _onTextChanged() {
    if (_programmaticTextChange) return;
    final query = _searchController.text;
    if (query.trim().isEmpty) {
      _searchService.cancelSearch();
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      _clearNearbyMarkers();
      _clearSelectedMarker();
      _restoreOverlay();
      _loadHistory();
      return;
    }
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _panelState = SearchPanelState.history;
      });
      return;
    }
    _searchService.debounceSearchSmart(
      query,
      lat: _currentPosition?.latitude,
      lng: _currentPosition?.longitude,
      onLoading: () {
        if (mounted) setState(() => _panelState = SearchPanelState.loading);
      },
      onResults: (results) {
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searchError = null;
            _panelState = SearchPanelState.results;
          });
          _clearOverlay();
          _updateNearbyMarkers(results);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _searchError = error;
            _searchResults = [];
            _panelState = SearchPanelState.error;
          });
        }
      },
    );
  }

  Future<void> _loadHistory() async {
    final history = await _searchService.getHistory();
    if (mounted) {
      setState(() {
        _searchHistory = history;
        _panelState = SearchPanelState.history;
      });
    }
  }

  void _onResultSelected(SearchResult result) {
    _programmaticTextChange = true;
    _searchController.text = result.name;
    _programmaticTextChange = false;
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    _searchService.cancelSearch();
    _searchService.addToHistory(result);

    // Clear category selection
    _clearCategoryState();

    setState(() {
      _searchResults = [];
      _searchError = null;
      _highlightedResult = result;
      _isFollowingLocation = false;
    });

    _clearNearbyMarkers();

    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(result.position.latitude, result.position.longitude),
        16.0,
      ),
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _showPremiumBottomSheet(result);
    });
  }

  void _onHistorySelected(SearchResult result) {
    _programmaticTextChange = true;
    _searchController.text = result.name;
    _programmaticTextChange = false;
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    _searchService.cancelSearch();

    // Clear category selection
    _clearCategoryState();

    setState(() {
      _searchResults = [];
      _searchError = null;
      _highlightedResult = result;
      _isFollowingLocation = false;
    });

    _clearNearbyMarkers();

    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(result.position.latitude, result.position.longitude),
        16.0,
      ),
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _showPremiumBottomSheet(result);
    });
  }

  void _showPremiumBottomSheet(SearchResult result) {
    _showSelectedMarker(result);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PremiumBottomSheet(
          result: result,
          onNavigate: () {
            Navigator.pop(context);
            final origin = _currentPosition != null
                ? latlong2.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : const latlong2.LatLng(28.6139, 77.2090);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RouteSelectionScreen(
                  origin: origin,
                  destination: latlong2.LatLng(result.position.latitude, result.position.longitude),
                  destinationName: result.name,
                ),
              ),
            );
          },
          onAddReview: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewFormScreen(
                  targetId: result.id,
                  targetName: result.name,
                  targetType: ReviewTargetType.place,
                  latitude: result.position.latitude,
                  longitude: result.position.longitude,
                ),
              ),
            );
          },
          onViewReviews: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityReviewsScreen(
                  targetId: result.id,
                  targetName: result.name,
                  isRoad: false,
                  latitude: result.position.latitude,
                  longitude: result.position.longitude,
                ),
              ),
            );
          },
          onShare: () async {
            final doc = await FirestoreService().getPlaceDoc(result.id);
            final data = doc.data() as Map<String, dynamic>?;
            if (!mounted) return;
            SafetyReportShare.share(
              name: result.name,
              latitude: result.position.latitude,
              longitude: result.position.longitude,
              aiScore: data?['score'] as int?,
              aiSummary: data?['summary'] as String?,
              reviewCount: data?['reviewCount'] as int? ?? 0,
            );
          },
          onClose: () {
            Navigator.pop(context);
            _clearSelectedMarker();
          },
        ),
      ).whenComplete(() => _clearSelectedMarker());
    });
  }

  void _onRemoveHistoryItem(SearchResult result) {
    _searchService.removeHistoryItem(result);
    _loadHistory();
  }

  void _onClearHistory() {
    _searchService.clearHistory();
    _loadHistory();
  }

  void _onCloseSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    _searchService.cancelSearch();
    setState(() {
      _searchResults = [];
      _searchError = null;
    });
    _clearNearbyMarkers();
    _clearSelectedMarker();
    _restoreOverlay();
  }

  // ── Category Quick Actions ────────────────────────────────────

  void _onCategoryTap(SearchCategory category) {
    HapticFeedback.lightImpact();

    if (_selectedCategory == category) {
      // Deselect
      setState(() {
        _selectedCategory = null;
      });
      _clearNearbyMarkers();
      _restoreOverlay();
      return;
    }

    setState(() {
      _selectedCategory = category;
    });

    _clearOverlay();
    _clearNearbyMarkers();
    _searchCategoryNearby(category);
  }

  void selectCategory(SearchCategory category) {
    if (!mounted) return;
    if (_currentPosition == null) {
      _onCurrentLocationPressed();
      // Wait for location to actually arrive before triggering category search
      _waitForLocation().then((_) {
        if (mounted) _onCategoryTap(category);
      });
      return;
    }
    _onCategoryTap(category);
  }

  Future<void> _waitForLocation() async {
    // If already available, return immediately
    if (_currentPosition != null) return;

    // Wait up to 10 seconds for location to arrive via stream
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_currentPosition != null || !mounted) return;
    }
  }

  Future<void> _searchCategoryNearby(SearchCategory category) async {
    if (_currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location not available. Tap the location button to enable.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final lat = _currentPosition!.latitude;
    final lng = _currentPosition!.longitude;

    debugPrint('[Category] Searching: ${category.name} | lat=$lat, lng=$lng');

    // Use NearbySearchService — same 4-tier pipeline everywhere
    List<SearchResult> results = [];
    try {
      if (category == SearchCategory.safeArea) {
        results = await _fetchSafeAreas(lat, lng);
      } else {
        final nearbySearch = NearbySearchService();
        results = await nearbySearch.searchCategory(category, lat: lat, lng: lng);
        debugPrint('[Category] NearbySearchService results: ${results.length}');
      }
    } catch (e) {
      debugPrint('[Category] Search error: $e');
    }

    // Filter out generic unhelpful names (skip for safe areas — they're already curated)
    if (category != SearchCategory.safeArea) {
      results = results.where((r) => !SearchResult.isGenericName(r.name)).toList();
    }

    debugPrint('[Category] Results: ${results.length}');

    if (!mounted) return;

    setState(() {
    });

    if (results.isEmpty) {
      final catName = SearchResult.categoryName(category).toLowerCase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No nearby $catName found'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Open the Quick Action list sheet (no markers on map yet)
    _showQuickActionListSheet(category, results);
  }

  Future<List<SearchResult>> _fetchSafeAreas(double lat, double lng) async {
    final userLoc = latlong2.LatLng(lat, lng);
    final scored = <MapEntry<SearchResult, int>>[];

    // Try Firestore first
    try {
      final snap = await FirebaseFirestore.instance.collection('places').get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final score = data['score'];
        if (score == null) continue;

        final scoreVal = score is int ? score : (score as num?)?.toInt();
        if (scoreVal == null || scoreVal == 0) continue;

        final id = doc.id;
        if (!id.startsWith('geo_')) continue;
        final coords = id.substring(4).split('_');
        if (coords.length < 2) continue;
        final placeLat = double.tryParse(coords[0]);
        final placeLng = double.tryParse(coords[1]);
        if (placeLat == null || placeLng == null) continue;

        final placeLoc = latlong2.LatLng(placeLat, placeLng);
        final dist = const latlong2.Distance().distance(userLoc, placeLoc);
        if (dist > 15000) continue;

        final name = data['name'] as String? ??
            doc.id.replaceAll('_', ' ').replaceAll('geo ', '');

        scored.add(MapEntry(SearchResult(
          id: id,
          name: name,
          address: '',
          position: placeLoc,
          distance: dist,
          category: SearchCategory.safeArea,
          icon: '🛡️',
          safetyScore: scoreVal,
        ), scoreVal));
      }
    } catch (e) {
      debugPrint('[Category] Firestore safe areas error: $e');
    }

    // If Firestore had scored places, use them
    if (scored.isNotEmpty) {
      scored.sort((a, b) {
        if (a.value != b.value) return b.value.compareTo(a.value);
        return (a.key.distance ?? 0).compareTo(b.key.distance ?? 0);
      });
      return scored.map((e) => e.key).toList();
    }

    // Fallback: Overpass spatial search for parks, playgrounds, community centres
    debugPrint('[Category] No Firestore scored places, falling back to Overpass');
    try {
      final nearbySearch = NearbySearchService();
      final overpassResults = await nearbySearch.searchCategory(
        SearchCategory.safeArea,
        lat: lat,
        lng: lng,
      );
      if (overpassResults.isNotEmpty) return overpassResults;
    } catch (e) {
      debugPrint('[Category] Overpass safe areas fallback error: $e');
    }

    // Final fallback: text search
    try {
      final textResults = await _searchService.search(
        'park $lat $lng',
        lat: lat,
        lng: lng,
      );
      return textResults;
    } catch (_) {
      return [];
    }
  }


  void _clearCategoryState() {
    setState(() {
      _selectedCategory = null;
    });
    _clearNearbyMarkers();
  }

  void _showQuickActionListSheet(
      SearchCategory category, List<SearchResult> results) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickActionListSheet(
        category: category,
        results: results,
        onClose: () => Navigator.pop(context),
        onResultSelected: (result) {
          Navigator.pop(context);
          _onQuickActionResultSelected(result);
        },
      ),
    );
  }

  void _onQuickActionResultSelected(SearchResult result) {
    // 1. Clear any existing markers
    _clearNearbyMarkers();

    // 2. Set highlighted result and clear search state
    setState(() {
      _highlightedResult = result;
      _searchResults = [];
      _isFollowingLocation = false;
    });

    // 3. Animate camera to the selected place
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(result.position.latitude, result.position.longitude),
        16.0,
      ),
      duration: const Duration(milliseconds: 600),
    );

    // 4. After camera settles, show single marker + place details sheet
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _showPremiumBottomSheet(result);
    });
  }

  void _onMapTapped(Point<double> point, LatLng latLng) async {
    if (_searchFocused) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    }

    final controller = _mapCtrl;
    if (controller == null) return;

    MapLayerConfig.logTapDebug(
      'TAP at screen(${point.x.toStringAsFixed(1)}, ${point.y.toStringAsFixed(1)}) '
      'geo(${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)})',
    );

    await MapLayerConfig.logAllFeaturesAtPoint(controller, point);

    // 1. Check nearby search result markers (our GeoJSON layers)
    if (_searchResults.isNotEmpty) {
      try {
        final features = await controller.queryRenderedFeatures(
          point,
          ['nearby-markers-dots', 'nearby-markers-labels'],
          null,
        );

        String? tappedId;
        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>?;
          final id = props?['id'] as String?;
          if (id != null) {
            tappedId = id;
            break;
          }
        }

        if (tappedId == null) {
          double minDist = double.infinity;
          for (final r in _searchResults) {
            final screenPt = await controller.toScreenLocation(
              LatLng(r.position.latitude, r.position.longitude),
            );
            final dx = screenPt.x - point.x;
            final dy = screenPt.y - point.y;
            final dist = dx * dx + dy * dy;
            if (dist < minDist) {
              minDist = dist;
              tappedId = r.id;
            }
          }
          if (minDist > 900) tappedId = null;
        }

        if (tappedId != null) {
          final match = _searchResults.where((r) => r.id == tappedId);
          if (match.isNotEmpty) {
            final result = match.first;
            MapLayerConfig.logTapDebug('HIT: nearby search marker → ${result.name}');
            setState(() {
              _highlightedResult = result;
            });
            // Keep category markers visible; only clear for text search
            if (_selectedCategory == null) {
              _clearNearbyMarkers();
              _restoreOverlay();
            }
            _mapCtrl?.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(result.position.latitude, result.position.longitude),
                16.0,
              ),
              duration: const Duration(milliseconds: 400),
            );
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _showPremiumBottomSheet(result);
            });
            return;
          }
        }
      } catch (_) {}
    }

    // 2. Check overlay locality labels (our GeoJSON overlay)
    try {
      final overlayFeatures = await controller.queryRenderedFeatures(
        point,
        ['overlay-dots', 'overlay-labels'],
        null,
      );
      if (overlayFeatures.isNotEmpty) {
        final props = overlayFeatures.first['properties'] as Map<String, dynamic>?;
        final name = props?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          MapLayerConfig.logTapDebug('HIT: overlay label → $name');
          _showLabelReviewPopup(name, latLng);
          return;
        }
      }
    } catch (_) {}

    // 3. Check dynamic education labels (our custom red labels)
    try {
      final eduFeatures = await controller.queryRenderedFeatures(
        point,
        ['dynamic-edu-labels'],
        null,
      );
      if (eduFeatures.isNotEmpty) {
        final props = eduFeatures.first['properties'] as Map<String, dynamic>?;
        final name = props?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          MapLayerConfig.logTapDebug('HIT: dynamic edu label → $name');
          _showLabelReviewPopup(name, latLng);
          return;
        }
      }
    } catch (_) {}

    // 4. Check MapTiler POI + place + road label layers (verified IDs)
    try {
      final placeFeatures = await controller.queryRenderedFeatures(
        point,
        MapLayerConfig.allPlaceLayers,
        null,
      );
      if (placeFeatures.isNotEmpty) {
        final props = placeFeatures.first['properties'] as Map<String, dynamic>?;
        final name = props?['name'] as String?;
        if (name != null && name.isNotEmpty) {
          MapLayerConfig.logTapDebug('HIT: place label → $name');
          _showLabelReviewPopup(name, latLng);
          return;
        }
      }
    } catch (_) {}

    // 5. Check MapTiler road label + geometry layers (generous radius)
    MapLayerConfig.logTapDebug('STEP 5: Querying road layers with generous radius');
    try {
      // Query multiple points in a grid around the tap for generous mobile tapping
      final screenX = point.x;
      final screenY = point.y;
      final radius = 50.0; // pixels — generous finger-friendly radius
      final step = 25.0; // grid spacing

      final Set<String> seenFeatures = {};
      final List<Map<String, dynamic>> roadCandidates = [];

      for (double dx = -radius; dx <= radius; dx += step) {
        for (double dy = -radius; dy <= radius; dy += step) {
          final queryPoint = Point(screenX + dx, screenY + dy);
          try {
            final features = await controller.queryRenderedFeatures(
              queryPoint,
              MapLayerConfig.allRoadLayers,
              null,
            );
            for (final f in features) {
              final key = f.toString();
              if (!seenFeatures.contains(key)) {
                seenFeatures.add(key);
                roadCandidates.add(f);
              }
            }
          } catch (_) {}
        }
      }

      MapLayerConfig.logTapDebug('STEP 5 RESULT: ${roadCandidates.length} unique road features in radius');

      if (roadCandidates.isNotEmpty) {
        // Find nearest road to tap point
        final nearest = await _findNearestRoad(controller, roadCandidates, point, latLng);

        if (nearest != null) {
          final feature = nearest.$1;
          final tapLatLng = nearest.$2;
          final props = feature['properties'] as Map<String, dynamic>?;
          final name = props?['name'] as String? ?? props?['ref'] as String?;
          final roadClass = props?['class'] as String? ?? '';
          MapLayerConfig.logTapDebug(
            'STEP 5 HIT: nearest road → ${name ?? 'unnamed'} (class=$roadClass, distance=${nearest.$3.toStringAsFixed(1)}px)',
          );

          final zoneId = await FirestoreService().resolveNearestRoadZone(
            roadName: name,
            latitude: tapLatLng.latitude,
            longitude: tapLatLng.longitude,
            roadClass: roadClass,
          );
          MapLayerConfig.logTapDebug('STEP 6: resolveNearestRoadZone → $zoneId');

          _showRoadBottomSheet(
            zoneId,
            latlong2.LatLng(tapLatLng.latitude, tapLatLng.longitude),
            name,
          );
          MapLayerConfig.logTapDebug('STEP 7: _showRoadBottomSheet called');
          return;
        }
      }

      MapLayerConfig.logTapDebug('STEP 5: No road features found in radius');
    } catch (e) {
      MapLayerConfig.logTapDebug('STEP 5 ERROR: $e');
    }

    // 6. Fallback: clear selection and detect road via Overpass
    MapLayerConfig.logTapDebug('NO HIT — falling back to Overpass road detection');
    _clearSelectedMarker();
    if (_selectedCategory == null) {
      _clearNearbyMarkers();
      _restoreOverlay();
    }
    setState(() {
      _highlightedResult = null;
    });

    _detectRoadAndShowSheet(latlong2.LatLng(latLng.latitude, latLng.longitude));
  }

  void _showLabelReviewPopup(String name, LatLng tapLocation) {
    final category = _inferCategoryFromName(name);
    final result = SearchResult(
      id: 'label_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}',
      name: name,
      address: '',
      position: latlong2.LatLng(tapLocation.latitude, tapLocation.longitude),
      category: category,
      icon: SearchResult.categoryIcon(category),
    );

    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(tapLocation.latitude, tapLocation.longitude),
        16.0,
      ),
      duration: const Duration(milliseconds: 400),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _showPremiumBottomSheet(result);
    });
  }

  SearchCategory _inferCategoryFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('hospital') || lower.contains('clinic') || lower.contains('medical')) {
      return SearchCategory.hospital;
    }
    if (lower.contains('school') || lower.contains('college') || lower.contains('university') || lower.contains('academy') || lower.contains('institute')) {
      return SearchCategory.school;
    }
    if (lower.contains('railway') || lower.contains('station')) {
      return SearchCategory.railwayStation;
    }
    if (lower.contains('police') || lower.contains('thana')) {
      return SearchCategory.police;
    }
    if (lower.contains('park') || lower.contains('garden')) {
      return SearchCategory.park;
    }
    if (lower.contains('mall') || lower.contains('market') || lower.contains('shop')) {
      return SearchCategory.mall;
    }
    if (lower.contains('restaurant') || lower.contains('food') || lower.contains('cafe')) {
      return SearchCategory.restaurant;
    }
    if (lower.contains('bank') || lower.contains('atm')) {
      return SearchCategory.bank;
    }
    if (lower.contains('hotel') || lower.contains('lodge')) {
      return SearchCategory.hotel;
    }
    if (lower.contains('bus')) {
      return SearchCategory.busStand;
    }
    return SearchCategory.general;
  }

  Future<void> _detectRoadAndShowSheet(latlong2.LatLng latLng) async {
    MapLayerConfig.logTapDebug('OVERPASS: Starting road detection at (${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)})');
    try {
      final query = '''
[out:json][timeout:5];
way(around:30,${latLng.latitude},${latLng.longitude})["highway"];
out body 1;
''';

      final response = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 5));

      MapLayerConfig.logTapDebug('OVERPASS: Response status=${response.statusCode}');

      if (response.statusCode != 200) {
        MapLayerConfig.logTapDebug('OVERPASS: FAILED — non-200 status');
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];
      MapLayerConfig.logTapDebug('OVERPASS: Found ${elements.length} elements');

      if (elements.isEmpty) {
        MapLayerConfig.logTapDebug('OVERPASS: No roads within 30m');
        return;
      }

      final element = elements.first;
      final tags = element['tags'] as Map<String, dynamic>? ?? {};
      final roadName = tags['name'] as String?;
      MapLayerConfig.logTapDebug('OVERPASS: Road name="${roadName ?? 'unnamed'}"');

      if (!mounted) return;

      final zoneId = await FirestoreService().resolveNearestRoadZone(
        roadName: roadName,
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
      MapLayerConfig.logTapDebug('OVERPASS: resolveNearestRoadZone → $zoneId');

      _showRoadBottomSheet(zoneId, latLng, roadName);
      MapLayerConfig.logTapDebug('OVERPASS: _showRoadBottomSheet called');
    } catch (e) {
      MapLayerConfig.logTapDebug('OVERPASS ERROR: $e');
    }
  }

  void _showRoadBottomSheet(String zoneId, latlong2.LatLng position, String? roadName) {
    final displayName = roadName ?? 'Road Segment';
    MapLayerConfig.logTapDebug('BOTTOM SHEET: Opening for zoneId=$zoneId, roadName=$displayName');

    final roadResult = SearchResult(
      id: 'road_${zoneId}',
      name: displayName,
      address: '',
      position: position,
      category: SearchCategory.general,
      icon: SearchResult.categoryIcon(SearchCategory.general),
    );
    _showSelectedMarker(roadResult);

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => RoadBottomSheet(
          roadZoneId: zoneId,
          position: position,
          roadName: displayName,
          onNavigate: () {
            Navigator.pop(context);
            final origin = _currentPosition != null
                ? latlong2.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : const latlong2.LatLng(28.6139, 77.2090);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RouteSelectionScreen(
                  origin: origin,
                  destination: latlong2.LatLng(position.latitude, position.longitude),
                  destinationName: displayName,
                ),
              ),
            );
          },
          onAddReview: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewFormScreen(
                  targetId: zoneId,
                  targetName: displayName,
                  targetType: ReviewTargetType.road,
                  latitude: position.latitude,
                  longitude: position.longitude,
                ),
              ),
            );
          },
          onViewReviews: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityReviewsScreen(
                  targetId: zoneId,
                  targetName: displayName,
                  isRoad: true,
                  latitude: position.latitude,
                  longitude: position.longitude,
                ),
              ),
            );
          },
          onShare: () async {
            final doc = await FirestoreService().getRoadZoneDoc(zoneId);
            final data = doc.data() as Map<String, dynamic>?;
            if (!mounted) return;
            SafetyReportShare.share(
              name: displayName,
              latitude: position.latitude,
              longitude: position.longitude,
              aiScore: data?['aiScore'] as int?,
              aiSummary: data?['aiSummary'] as String?,
              reviewCount: data?['reviewCount'] as int? ?? 0,
            );
          },
          onClose: () {
            Navigator.pop(context);
            _clearSelectedMarker();
          },
        ),
      ).whenComplete(() => _clearSelectedMarker());
    });
  }

  /// Find the nearest road feature from candidates, using generous screen-space radius.
  /// Returns (feature, tapLatLng, screenDistance) or null.
  Future<(Map<String, dynamic>, LatLng, double)?> _findNearestRoad(
    MapLibreMapController controller,
    List<Map<String, dynamic>> features,
    Point<double> tapPoint,
    LatLng tapLatLng,
  ) async {
    double bestDist = double.infinity;
    Map<String, dynamic>? bestFeature;
    LatLng? bestLatLng;

    // Road class priority: higher = more important (motorway > primary > secondary > etc.)
    int bestClassPriority = -1;

    for (final f in features) {
      final geom = f['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;

      final coords = geom['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) continue;

      // Get the nearest point on this road's geometry to the tap
      double minDist = double.infinity;
      LatLng? nearestOnRoad;

      for (final coord in coords) {
        final c = coord as List<dynamic>;
        if (c.length < 2) continue;

        // Handle LineString (flat array of coords) or MultiLineString (array of arrays)
        List<dynamic> pointList;
        if (c[0] is List) {
          // This is a coordinate pair inside a nested array
          pointList = c;
        } else {
          pointList = [c];
        }

        for (final p in pointList) {
          if (p is! List || p.length < 2) continue;
          final lng = p[0] as double;
          final lat = p[1] as double;
          final roadPt = await controller.toScreenLocation(LatLng(lat, lng));
          final dx = roadPt.x - tapPoint.x;
          final dy = roadPt.y - tapPoint.y;
          final dist = dx * dx + dy * dy;
          if (dist < minDist) {
            minDist = dist;
            nearestOnRoad = LatLng(lat, lng);
          }
        }
      }

      if (minDist < bestDist) {
        bestDist = minDist;
        bestFeature = f;
        bestLatLng = nearestOnRoad;
        final props = f['properties'] as Map<String, dynamic>?;
        bestClassPriority = _roadClassPriority(props?['class'] as String? ?? '');
      } else if ((minDist - bestDist).abs() < 400) {
        // Nearly identical distance — prefer higher road class
        final props = f['properties'] as Map<String, dynamic>?;
        final classPriority = _roadClassPriority(props?['class'] as String? ?? '');
        if (classPriority > bestClassPriority) {
          bestDist = minDist;
          bestFeature = f;
          bestLatLng = nearestOnRoad;
          bestClassPriority = classPriority;
        }
      }
    }

    if (bestFeature == null || bestLatLng == null) return null;

    final screenDist = sqrt(bestDist);
    return (bestFeature, bestLatLng, screenDist);
  }

  static int _roadClassPriority(String roadClass) {
    switch (roadClass) {
      case 'motorway':
      case 'motorway_link':
        return 10;
      case 'trunk':
      case 'trunk_link':
        return 9;
      case 'primary':
      case 'primary_link':
        return 8;
      case 'secondary':
      case 'secondary_link':
        return 7;
      case 'tertiary':
      case 'tertiary_link':
        return 6;
      case 'residential':
      case 'unclassified':
        return 4;
      case 'service':
        return 3;
      case 'path':
      case 'track':
      case 'footway':
        return 1;
      default:
        return 5;
    }
  }

  void _onCurrentLocationPressed() {
    HapticFeedback.lightImpact();
    final controller = _mapCtrl;
    if (controller == null) return;

      controller.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

    final cached = _locationService.lastPosition;
    if (cached != null) {
      final latLng = LatLng(cached.latitude, cached.longitude);
      setState(() {
        _currentPosition = latLng;
        _isFollowingLocation = true;
      });
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 14.0),
        duration: const Duration(milliseconds: 700),
      ).then((_) {
        controller.animateCamera(
          CameraUpdate.bearingTo(0),
          duration: const Duration(milliseconds: 300),
        );
        controller.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      });
      return;
    }

    setState(() => _isLocating = true);
    _locationService.getCurrentLocation().then((position) {
      if (!mounted) return;
      setState(() => _isLocating = false);
      if (position == null) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = latLng;
        _isFollowingLocation = true;
      });
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 14.0),
        duration: const Duration(milliseconds: 700),
      ).then((_) {
        controller.animateCamera(
          CameraUpdate.bearingTo(0),
          duration: const Duration(milliseconds: 300),
        );
        controller.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      });
    });
  }

  void _onRecenterPressed() {
    if (_currentPosition == null) return;
    final controller = _mapCtrl;
    if (controller == null) return;

    controller.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(_currentPosition!, 14.0),
      duration: const Duration(milliseconds: 700),
    ).then((_) {
      controller.animateCamera(
        CameraUpdate.bearingTo(0),
        duration: const Duration(milliseconds: 300),
      );
      controller.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
    });
    setState(() => _isFollowingLocation = true);
  }

  void _onNorthReset() {
    _mapCtrl?.animateCamera(
      CameraUpdate.bearingTo(0),
      duration: const Duration(milliseconds: 400),
    );
  }

  bool _userLocationLayerReady = false;

  Map<String, dynamic> _buildUserLocationGeoJson() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [_currentPosition!.longitude, _currentPosition!.latitude],
      },
      'properties': {'accuracy': _currentAccuracy ?? 0.0},
    };
  }

  Future<void> _initUserLocationLayer() async {
    final controller = _mapCtrl;
    if (controller == null || _currentPosition == null) return;

    if (_userLocationLayerReady) {
      await controller.setGeoJsonSource('user-location', _buildUserLocationGeoJson());
      return;
    }

    try {
      await controller.removeLayer('user-dot');
      await controller.removeLayer('user-accuracy-circle');
      await controller.removeSource('user-location');
    } catch (_) {}

    await controller.addGeoJsonSource('user-location', _buildUserLocationGeoJson());

    await controller.addCircleLayer('user-location', 'user-dot',
      CircleLayerProperties(
        circleRadius: 7,
        circleColor: '#4285F4',
        circleStrokeWidth: 3,
        circleStrokeColor: '#FFFFFF',
        circleStrokeOpacity: 60,
      ),
    );

    _userLocationLayerReady = true;
  }

  Future<void> _updateUserLocationPosition() async {
    final controller = _mapCtrl;
    if (controller == null || _currentPosition == null) return;
    if (!_userLocationLayerReady) {
      await _initUserLocationLayer();
      return;
    }
    await controller.setGeoJsonSource('user-location', _buildUserLocationGeoJson());
  }

  static const String _selectedSourceId = 'selected-marker';

  Future<void> _showSelectedMarker(SearchResult result) async {
    final controller = _mapCtrl;
    if (controller == null) return;

    final geoJson = {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [result.position.longitude, result.position.latitude],
      },
      'properties': {
        'name': result.name,
      },
    };

    try {
      if (_selectedMarkerReady) {
        await controller.setGeoJsonSource(_selectedSourceId, geoJson);
        return;
      }

      await controller.addGeoJsonSource(_selectedSourceId, geoJson);

      // Shadow
      await controller.addCircleLayer(_selectedSourceId, '$_selectedSourceId-shadow',
        CircleLayerProperties(
          circleRadius: [
            'interpolate', ['linear'], ['zoom'],
            10, 10,
            14, 14,
            18, 18,
          ],
          circleColor: '#000000',
          circleOpacity: 20,
          circleTranslate: [0, 3],
          circlePitchAlignment: 'map',
        ),
      );

      // Red pin body
      await controller.addCircleLayer(_selectedSourceId, '$_selectedSourceId-pin',
        CircleLayerProperties(
          circleRadius: [
            'interpolate', ['linear'], ['zoom'],
            10, 8,
            14, 12,
            18, 16,
          ],
          circleColor: '#E53935',
          circleStrokeWidth: 2.5,
          circleStrokeColor: '#FFFFFF',
          circlePitchAlignment: 'map',
        ),
      );

      // White center dot
      await controller.addCircleLayer(_selectedSourceId, '$_selectedSourceId-center',
        CircleLayerProperties(
          circleRadius: [
            'interpolate', ['linear'], ['zoom'],
            10, 3,
            14, 4.5,
            18, 6,
          ],
          circleColor: '#FFFFFF',
          circlePitchAlignment: 'map',
        ),
      );

      _selectedMarkerReady = true;
    } catch (_) {}
  }

  Future<void> _clearSelectedMarker() async {
    final controller = _mapCtrl;
    if (controller == null || !_selectedMarkerReady) return;

    try {
      await controller.removeLayer('$_selectedSourceId-shadow');
      await controller.removeLayer('$_selectedSourceId-pin');
      await controller.removeLayer('$_selectedSourceId-center');
      await controller.removeSource(_selectedSourceId);
    } catch (_) {}
    _selectedMarkerReady = false;
  }

  Future<void> _updateNearbyMarkers(List<SearchResult> results) async {
    final controller = _mapCtrl;
    if (controller == null) return;

    if (results.isEmpty) {
      await _clearNearbyMarkers();
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final result in results) {
      if (_highlightedResult != null && result.id == _highlightedResult!.id) continue;

      final categoryColor = CategoryConfig.categoryColors[result.category] ?? Colors.grey;
      final colorHex = '#${categoryColor.toARGB32().toRadixString(16).substring(2, 8)}';

      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [result.position.longitude, result.position.latitude],
        },
        'properties': {
          'id': result.id,
          'icon': result.icon,
          'name': result.name,
          'color': colorHex,
        },
      });
    }

    if (features.isEmpty) {
      await _clearNearbyMarkers();
      return;
    }

    try {
      if (_nearbyMarkersReady) {
        await controller.setGeoJsonSource('nearby-markers', {
          'type': 'FeatureCollection',
          'features': features,
        });
        return;
      }

      await controller.addGeoJsonSource('nearby-markers', {
        'type': 'FeatureCollection',
        'features': features,
      });

      await controller.addCircleLayer('nearby-markers', 'nearby-markers-dots',
        CircleLayerProperties(
          circleRadius: [
            'interpolate', ['linear'], ['zoom'],
            10, 4,
            14, 6,
            18, 8,
          ],
          circleColor: ['get', 'color'],
          circleStrokeWidth: 2,
          circleStrokeColor: '#FFFFFF',
          circlePitchAlignment: 'map',
        ),
      );

      await controller.addSymbolLayer('nearby-markers', 'nearby-markers-labels',
        SymbolLayerProperties(
          textField: ['get', 'name'],
          textSize: [
            'interpolate', ['linear'], ['zoom'],
            10, 7,
            14, 9,
            18, 11,
          ],
          textColor: '#D32F2F',
          textFont: ['DIN Pro Medium', 'Arial Unicode MS Regular'],
          textOffset: [0, 1.8],
          textAnchor: 'top',
          textAllowOverlap: true,
          textIgnorePlacement: true,
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2,
          symbolZOrder: 'icon-optional',
        ),
      );

      _nearbyMarkersReady = true;
    } catch (_) {}
  }

  Future<void> _clearNearbyMarkers() async {
    final controller = _mapCtrl;
    if (controller == null || !_nearbyMarkersReady) return;

    try {
      await controller.removeLayer('nearby-markers-dots');
      await controller.removeLayer('nearby-markers-labels');
      await controller.removeSource('nearby-markers');
    } catch (_) {}
    _nearbyMarkersReady = false;
  }

  Future<void> _updateOverlay(List<OverlayPlace> places) async {
    final controller = _mapCtrl;
    if (controller == null) return;

    final features = <Map<String, dynamic>>[];
    for (final place in places) {
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [place.lng, place.lat],
        },
        'properties': {
          'name': place.name,
          'category': place.category.name,
          'priority': place.priority,
        },
      });
    }

    if (features.isEmpty) {
      await _clearOverlay();
      return;
    }

    try {
      if (!_overlayLayerReady) {
        await controller.addGeoJsonSource('locality-overlay', {
          'type': 'FeatureCollection',
          'features': features,
        });

        await controller.addCircleLayer('locality-overlay', 'overlay-dots',
          CircleLayerProperties(
            circleRadius: [
              'interpolate', ['linear'], ['zoom'],
              10, 2.5,
              14, 3.5,
              18, 4.5,
            ],
            circleColor: '#607D8B',
            circleOpacity: 180,
            circleStrokeWidth: 0.5,
            circleStrokeColor: '#FFFFFF',
            circleStrokeOpacity: 200,
            circlePitchAlignment: 'map',
          ),
        );

        await controller.addSymbolLayer('locality-overlay', 'overlay-labels',
          SymbolLayerProperties(
            textField: ['get', 'name'],
            textSize: [
              'interpolate', ['linear'], ['zoom'],
              10, 9,
              14, 10.5,
              18, 12,
            ],
            textColor: '#455A64',
            textFont: ['DIN Pro Medium', 'Arial Unicode MS Regular'],
            textOffset: [1.0, 0],
            textAnchor: 'left',
            textAllowOverlap: true,
            textIgnorePlacement: true,
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2,
            textHaloBlur: 0.5,
            symbolZOrder: 'icon-optional',
            symbolSpacing: 120,
          ),
        );

        _overlayLayerReady = true;
      } else {
        await controller.setGeoJsonSource('locality-overlay', {
          'type': 'FeatureCollection',
          'features': features,
        });
      }
    } catch (_) {}
  }

  Future<void> _clearOverlay() async {
    final controller = _mapCtrl;
    if (controller == null || !_overlayLayerReady) return;

    try {
      await controller.removeLayer('overlay-dots');
      await controller.removeLayer('overlay-labels');
      await controller.removeSource('locality-overlay');
    } catch (_) {}
    _overlayLayerReady = false;
  }

  void _restoreOverlay() {
    final controller = _mapCtrl;
    if (controller == null) return;
    final pos = controller.cameraPosition;
    if (pos == null) return;
    _overlayService.onCameraChanged(
      lat: pos.target.latitude,
      lng: pos.target.longitude,
      zoom: pos.zoom,
      onUpdate: (places) {
        if (mounted) _updateOverlay(places);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = _searchFocused;
    final showFab = !_searchFocused;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(28.6139, 77.2090),
              zoom: 14.0,
            ),
            styleString: 'https://api.maptiler.com/maps/streets-v2/style.json?key=${ApiKeys.mapTiler}',
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapTapped,
            trackCameraPosition: true,
            myLocationEnabled: false,
            myLocationTrackingMode: MyLocationTrackingMode.tracking,
            myLocationRenderMode: MyLocationRenderMode.normal,
            compassEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
            translucentTextureSurface: true,
          ),

          IgnorePointer(
            child: Column(
              children: [
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.ink.withValues(alpha: 0.28),
                        AppColors.ink.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.ink.withValues(alpha: 0.16),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),

          MapOverlays(
            currentZoom: _currentZoom,
            currentBearing: _currentBearing,
            isFollowingLocation: _isFollowingLocation,
            onRecenter: _onRecenterPressed,
            onNorthReset: _onNorthReset,
          ),

          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomSearchBar(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  onChanged: (_) {},
                  onClose: _onCloseSearch,
                  isSearching: _searchFocused,
                  avatarUrl: context.watch<AuthProvider>().appUser?.photoUrl,
                  onAvatarTap: () => showAuthPopup(context),
                ),
              ],
            ),
          ),

          if (showOverlay)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _panelSlide,
                child: FadeTransition(
                  opacity: _panelFade,
                  child: SearchResultsOverlay(
                    state: _panelState,
                    results: _searchResults,
                    history: _searchHistory,
                    errorMessage: _searchError,
                    currentQuery: _searchController.text,
                    onResultTap: _onResultSelected,
                    onHistoryTap: _onHistorySelected,
                    onRemoveHistory: _onRemoveHistoryItem,
                    onClearHistory: _onClearHistory,
                  ),
                ),
              ),
            ),

          if (showFab)
            Positioned(
              right: 16,
              bottom: 16,
              child: FadeTransition(
                opacity: _fabFade,
                child: LocationButton(
                  onPressed: _onCurrentLocationPressed,
                  isLoading: _isLocating,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
