import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../services/search_service.dart';
import '../services/nearby_search_service.dart';
import '../services/nearby_locality_cache.dart';
import '../services/safety_report_share.dart';
import '../services/firestore_service.dart';
import '../config/api_keys.dart';
import '../models/search_result.dart';
import '../theme/constants.dart';
import '../widgets/bottom_sheet.dart';
import '../screens/route_selection_screen.dart';
import '../screens/review_form_screen.dart';
import '../screens/community_reviews_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(SearchCategory category)? onQuickAction;
  const DashboardScreen({super.key, this.onQuickAction});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final PageController _carouselController;
  late final Timer _autoScrollTimer;
  bool _isHolding = false;
  int _currentCarouselPage = 1000;
  final int _realItemCount = 4;

  final LocationService _locationService = LocationService();
  late final NearbyLocalityCache _localityCache;
  late final SearchService _searchService;
  LatLng? _currentPosition;
  String _placeName = 'Fetching location...';
  String _placeDetail = '';
  String _cityName = 'Bhagalpur';
  bool _isLoadingLocation = true;
  MapLibreMapController? _miniMapController;

  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  bool _searchFocused = false;
  List<SearchResult> _searchResults = [];
  bool _searchLoading = false;
  bool _programmaticTextChange = false;

  int? _safetyScore;
  int _safetyReviewCount = 0;
  bool _isLoadingSafetyScore = true;

  final List<_QuickAction> _quickActions = [
    _QuickAction(
      Icons.local_police_outlined,
      'Police',
      SearchCategory.police,
      const Color(0xFF1E88E5),
      const Color(0xFFE3F2FD),
    ),
    _QuickAction(
      Icons.local_hospital_outlined,
      'Hospital',
      SearchCategory.hospital,
      const Color(0xFFE53935),
      const Color(0xFFFCE4EC),
    ),
    _QuickAction(
      Icons.park_outlined,
      'Safe Area',
      SearchCategory.safeArea,
      const Color(0xFF43A047),
      const Color(0xFFE8F5E9),
    ),
    _QuickAction(
      Icons.medication_outlined,
      'Pharmacy',
      SearchCategory.pharmacy,
      const Color(0xFFFF8F00),
      const Color(0xFFFFF3E0),
    ),
    _QuickAction(
      Icons.female_outlined,
      'Women Help',
      SearchCategory.womenHelp,
      const Color(0xFF8E24AA),
      const Color(0xFFF3E5F5),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _localityCache = NearbyLocalityCache();
    _searchService = SearchService(localityCache: _localityCache);
    _carouselController = PageController(
      viewportFraction: 0.38,
      initialPage: _currentCarouselPage,
    );
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isHolding && _carouselController.hasClients) {
        _currentCarouselPage++;
        _carouselController.animateToPage(
          _currentCarouselPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
    _fetchLocation();

    _searchFocusNode.addListener(_onSearchFocusChange);
    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _autoScrollTimer.cancel();
    _carouselController.dispose();
    _searchService.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    final cached = _locationService.lastPosition;
    if (cached != null) {
      final pos = LatLng(cached.latitude, cached.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLoadingLocation = false;
        });
        _reverseGeocode(pos.latitude, pos.longitude);
        _fetchSafetyScore(pos.latitude, pos.longitude);
      }
      return;
    }

    try {
      final position = await _locationService.getCurrentLocation();
      if (position != null && mounted) {
        final pos = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = pos;
          _isLoadingLocation = false;
        });
        _reverseGeocode(pos.latitude, pos.longitude);
        _fetchSafetyScore(pos.latitude, pos.longitude);
      } else if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _placeName = 'Location unavailable';
          _placeDetail = 'Enable location services';
          _isLoadingSafetyScore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _placeName = 'Location unavailable';
          _placeDetail = 'Enable location services';
          _isLoadingSafetyScore = false;
        });
      }
    }
  }

  Future<void> _fetchSafetyScore(double lat, double lng) async {
    try {
      debugPrint('[_fetchSafetyScore] lat=$lat, lng=$lng');
      final reviews = await FirestoreService().fetchNearbyReviews(lat, lng);
      debugPrint('[_fetchSafetyScore] reviews returned: ${reviews.length}');
      final avgRating = FirestoreService.calculateAverageRating(reviews);
      debugPrint('[_fetchSafetyScore] avgRating=$avgRating');

      if (mounted) {
        setState(() {
          _safetyReviewCount = reviews.length;
          // Convert 1-5 star average to 0-100 scale
          _safetyScore = avgRating != null ? (avgRating / 5.0 * 100).round() : null;
          _isLoadingSafetyScore = false;
        });
      }
    } catch (e) {
      debugPrint('[_fetchSafetyScore] error: $e');
      if (mounted) {
        setState(() {
          _isLoadingSafetyScore = false;
        });
      }
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeSakhi/1.0'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};
        final name = data['display_name'] as String? ?? '';
        final parts = <String>[];
        if (address['road'] != null) parts.add(address['road']);
        if (address['suburb'] != null) parts.add(address['suburb']);
        if (address['city'] != null) parts.add(address['city']);
        if (address['state'] != null) parts.add(address['state']);
        setState(() {
          _placeName = parts.isNotEmpty
              ? parts.first
              : (name.isNotEmpty ? name.split(',').first : 'Unknown location');
          _placeDetail = parts.length > 1
              ? parts.sublist(1).join(', ')
              : (name.contains(',')
                    ? name.split(',').skip(1).take(2).join(',').trim()
                    : '');
          _cityName = address['city'] as String? ??
              address['town'] as String? ??
              address['village'] as String? ??
              address['suburb'] as String? ??
              'Bhagalpur';
        });
      }
    } catch (_) {}
  }

  void _onSearchFocusChange() {
    final focused = _searchFocusNode.hasFocus;
    if (mounted) setState(() => _searchFocused = focused);
  }

  void _onSearchTextChanged() {
    if (_programmaticTextChange) return;
    final query = _searchController.text;
    if (query.trim().length < 2) {
      _searchService.cancelSearch();
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    _searchService.debounceSearchSmart(
      query,
      lat: _currentPosition?.latitude,
      lng: _currentPosition?.longitude,
      onLoading: () {
        if (mounted) setState(() => _searchLoading = true);
      },
      onResults: (results) {
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searchLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _searchLoading = false);
      },
    );
  }

  void _onSearchResultSelected(SearchResult result) {
    _programmaticTextChange = true;
    _searchController.text = result.name;
    _programmaticTextChange = false;
    _searchFocusNode.unfocus();
    _searchService.addToHistory(result);
    setState(() => _searchResults = []);

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
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  void _onSearchClose() {
    _programmaticTextChange = true;
    _searchController.clear();
    _programmaticTextChange = false;
    _searchFocusNode.unfocus();
    setState(() => _searchResults = []);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _userName() {
    final user = context.read<AuthProvider>().appUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName!.split(' ').first;
    }
    return 'Sakhi';
  }

  Future<void> _showNearbyPlacesBottomSheet(SearchCategory category) async {
    if (_currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location not available'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final lat = _currentPosition!.latitude;
    final lng = _currentPosition!.longitude;

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CategoryPlacesBottomSheet(
          category: category,
          lat: lat,
          lng: lng,
          cityName: _cityName,
          searchService: _searchService,
          onPlaceSelected: (result) {
            Navigator.pop(context);
            _showPlaceDetails(result);
          },
        ),
      );
    }
  }

  void _showPlaceDetails(SearchResult result) {
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
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxH = constraints.maxHeight;
            final compact = maxH < 700;
            final sectionGap = compact ? 8.0 : 12.0;

            final contentHeight =
                (compact ? 50.0 : 56.0) +  // brand header
                (compact ? 28.0 : 32.0) +  // greeting
                sectionGap +               // gap after greeting
                48.0 +                     // search bar
                sectionGap +               // gap after search
                (compact ? 18.0 : 19.0) +  // section title
                (compact ? 8.0 : 10.0) +   // gap after title
                (compact ? 92.0 : 98.0) +  // carousel
                sectionGap +               // gap after carousel
                (compact ? 86.0 : 96.0) +  // safety score card
                sectionGap;                // gap before location card

            final remainingH = maxH - contentHeight;
            final mapHeight = remainingH > 200 ? remainingH - 60 : (compact ? 82.0 : 160.0);

            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: maxH),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, compact ? 8 : 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBrandHeader(compact),
                    SizedBox(height: compact ? 4 : 6),
                    _buildGreeting(compact),
                    SizedBox(height: sectionGap),
                    _buildSearchBar(),
                    SizedBox(height: sectionGap),
                    Text(
                      'Explore Safe Heaven',
                      style: TextStyle(
                        fontSize: compact ? 15 : 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    _buildCarousel(compact: compact),
                    SizedBox(height: sectionGap),
                    _buildSafetyScoreCard(compact: compact),
                    SizedBox(height: sectionGap),
                    _buildLocationCard(compact: compact, mapHeight: mapHeight),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandHeader(bool compact) {
    final logoSize = compact ? 44.0 : 50.0;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/app_icon.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Safe Sakhi',
          style: TextStyle(
            fontSize: compact ? 24 : 26,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildGreeting(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting()}, ${_userName()}',
          style: TextStyle(
            fontSize: compact ? 23 : 25,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Stay safe, stay connected.',
          style: TextStyle(
            fontSize: compact ? 13 : 14,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final photoUrl = context.watch<AuthProvider>().appUser?.photoUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _searchFocused
                  ? AppColors.primaryBlue.withValues(alpha: 0.3)
                  : AppColors.borderColor.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: _searchFocused ? 0.08 : 0.04),
                blurRadius: _searchFocused ? 12 : 8,
                offset: Offset(0, _searchFocused ? 4 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              if (_searchFocused)
                GestureDetector(
                  onTap: _onSearchClose,
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.primaryBlue, size: 22),
                )
              else
                Icon(Icons.search_rounded, color: AppColors.textHint, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Search safe places nearby',
                    hintStyle: TextStyle(fontSize: 15, color: AppColors.textHint.withValues(alpha: 0.7)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_searchFocused && _searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _programmaticTextChange = true;
                    _searchController.clear();
                    _programmaticTextChange = false;
                    setState(() => _searchResults = []);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, color: AppColors.textHint, size: 18),
                  ),
                ),
              if (photoUrl != null && photoUrl.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 32,
                  height: 32,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.scaffoldBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 18),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 20),
                ),
            ],
          ),
        ),
        if (_searchFocused && (_searchResults.isNotEmpty || _searchLoading))
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: AppColors.ink.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: _searchLoading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryBlue)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      final categoryColor = CategoryConfig.categoryColors[result.category] ?? AppColors.textHint;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _onSearchResultSelected(result);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: categoryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    SearchResult.categoryIcon(result.category) == '📍'
                                        ? Icons.location_on_outlined
                                        : Icons.place_outlined,
                                    color: categoryColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        result.name,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (result.address.isNotEmpty)
                                        Text(
                                          result.address,
                                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (result.displayDistance.isNotEmpty)
                                  Text(
                                    result.displayDistance,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  Widget _buildCarousel({required bool compact}) {
    return SizedBox(
      height: compact ? 92 : 98,
      child: GestureDetector(
        onLongPressStart: (_) => setState(() => _isHolding = true),
        onLongPressEnd: (_) => setState(() => _isHolding = false),
        onLongPressCancel: () => setState(() => _isHolding = false),
        child: PageView.builder(
          controller: _carouselController,
          itemBuilder: (context, index) {
            final action = _quickActions[index % _realItemCount];
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showNearbyPlacesBottomSheet(action.category);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  children: [
                    Container(
                      width: compact ? 52 : 56,
                      height: compact ? 52 : 56,
                      decoration: BoxDecoration(
                        color: action.bgColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        action.icon,
                        color: action.iconColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSafetyScoreCard({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT STATUS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Safety Score',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                if (_isLoadingSafetyScore)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: compact ? 28 : 32,
                        height: compact ? 28 : 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.safeGreen.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  )
                else if (_safetyScore != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$_safetyScore',
                        style: TextStyle(
                          fontSize: compact ? 32 : 36,
                          fontWeight: FontWeight.w900,
                          color: _safetyScore! >= 75
                              ? AppColors.safeGreen
                              : _safetyScore! >= 50
                                  ? const Color(0xFFFFA726)
                                  : AppColors.errorRed,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '/100 \u2022 $_safetyReviewCount review${_safetyReviewCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Not enough reviews available',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.safeGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppColors.safeGreen,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard({
    required bool compact,
    required double mapHeight,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primaryBlue,
                  size: 14,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'YOUR LOCATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHint,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: mapHeight,
              width: double.infinity,
              child: _isLoadingLocation
                  ? Container(
                      color: AppColors.scaffoldBackground,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    )
                  : _currentPosition != null
                  ? Stack(
                      children: [
                        MapLibreMap(
                          initialCameraPosition: CameraPosition(
                            target: _currentPosition!,
                            zoom: 15.0,
                          ),
                          styleString:
                              'https://api.maptiler.com/maps/streets-v2/style.json?key=${ApiKeys.mapTiler}',
                          onMapCreated: (controller) =>
                              _miniMapController = controller,
                          rotateGesturesEnabled: false,
                          scrollGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          logoEnabled: false,
                          myLocationEnabled: false,
                          onStyleLoadedCallback: () {
                            if (_miniMapController != null &&
                                _currentPosition != null) {
                              _addMarker(_currentPosition!);
                            }
                          },
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.borderColor.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: AppColors.scaffoldBackground,
                      child: const Center(
                        child: Icon(
                          Icons.location_off_rounded,
                          color: AppColors.textHint,
                          size: 32,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _placeName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_placeDetail.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        _placeDetail,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primaryBlue,
                  size: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addMarker(LatLng position) async {
    if (_miniMapController == null) return;
    try {
      await _miniMapController!.addCircle(
        CircleOptions(
          geometry: position,
          circleRadius: 8,
          circleColor: '#2457E6',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );
    } catch (_) {}
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final SearchCategory category;
  final Color iconColor;
  final Color bgColor;
  const _QuickAction(
    this.icon,
    this.label,
    this.category,
    this.iconColor,
    this.bgColor,
  );
}

class _CategoryPlacesBottomSheet extends StatefulWidget {
  final SearchCategory category;
  final double lat;
  final double lng;
  final String? cityName;
  final SearchService searchService;
  final void Function(SearchResult) onPlaceSelected;

  const _CategoryPlacesBottomSheet({
    required this.category,
    required this.lat,
    required this.lng,
    this.cityName,
    required this.searchService,
    required this.onPlaceSelected,
  });

  @override
  State<_CategoryPlacesBottomSheet> createState() => _CategoryPlacesBottomSheetState();
}

class _CategoryPlacesBottomSheetState extends State<_CategoryPlacesBottomSheet> {
  bool _loading = true;
  List<SearchResult> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchPlaces();
  }

  Future<void> _searchPlaces() async {
    try {
      final nearbySearch = NearbySearchService();
      List<SearchResult> results = [];

      debugPrint('[UI] _searchPlaces: category=${widget.category.name}, lat=${widget.lat}, lng=${widget.lng}, cityName=${widget.cityName}');
      results = await nearbySearch.searchCategory(
        widget.category,
        lat: widget.lat,
        lng: widget.lng,
        cityName: widget.cityName,
      );
      debugPrint('[UI] Results from NearbySearchService: ${results.length}');
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        debugPrint('  [UI] BEFORE_FILTER[$i]: "${r.name}", cat=${r.category.name}, dist=${r.distance?.toStringAsFixed(0)}m');
      }

      // Filter generic names
      final beforeGenericFilter = results.length;
      results = results.where((r) => !SearchResult.isGenericName(r.name)).toList();
      debugPrint('[UI] After generic name filter: ${results.length} (removed ${beforeGenericFilter - results.length})');

      if (mounted) {
        setState(() {
          _results = results.take(15).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to search nearby places';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _categoryColor(widget.category);
    final categoryIcon = _categoryIcon(widget.category);
    final categoryName = SearchResult.categoryName(widget.category);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby $categoryName',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${_results.length} places found',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.textHint.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color: categoryColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Searching nearby $categoryName...',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: AppColors.textHint.withValues(alpha: 0.4)),
                                const SizedBox(height: 8),
                                Text(
                                  'No nearby $categoryName found',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              final userLoc = latlong2.LatLng(widget.lat, widget.lng);
                              final dist = const latlong2.Distance().distance(userLoc, result.position);
                              final distText = dist < 1000
                                  ? '${dist.round()} m'
                                  : '${(dist / 1000).toStringAsFixed(1)} km';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    widget.onPlaceSelected(result);
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.scaffoldBackground,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: categoryColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(categoryIcon, color: categoryColor, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                result.name,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (result.address.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  result.address,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              distText,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: categoryColor,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColors.textHint.withValues(alpha: 0.5),
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(SearchCategory category) {
    return switch (category) {
      SearchCategory.police => const Color(0xFF1E88E5),
      SearchCategory.hospital => const Color(0xFFE53935),
      SearchCategory.safeArea => const Color(0xFF43A047),
      SearchCategory.pharmacy => const Color(0xFFFF8F00),
      SearchCategory.womenHelp => const Color(0xFF8E24AA),
      _ => AppColors.primaryBlue,
    };
  }

  IconData _categoryIcon(SearchCategory category) {
    return switch (category) {
      SearchCategory.police => Icons.local_police_outlined,
      SearchCategory.hospital => Icons.local_hospital_outlined,
      SearchCategory.safeArea => Icons.park_outlined,
      SearchCategory.pharmacy => Icons.medication_outlined,
      SearchCategory.womenHelp => Icons.female_outlined,
      _ => Icons.location_on_outlined,
    };
  }
}
