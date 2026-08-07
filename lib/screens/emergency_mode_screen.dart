import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../config/api_keys.dart';
import '../models/emergency_contact.dart';
import '../models/search_result.dart';
import '../services/emergency_service.dart';
import '../services/firestore_service.dart';
import '../services/nearby_search_service.dart';
import '../theme/constants.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/emergency_status_card.dart';
import 'community_reviews_screen.dart';
import 'emergency_contact_screen.dart';
import 'review_form_screen.dart';
import 'route_selection_screen.dart';
import '../services/safety_report_share.dart';

class EmergencyModeScreen extends StatefulWidget {
  final bool autoCall;

  const EmergencyModeScreen({super.key, this.autoCall = false});

  @override
  State<EmergencyModeScreen> createState() => _EmergencyModeScreenState();
}

class _EmergencyModeScreenState extends State<EmergencyModeScreen>
    with SingleTickerProviderStateMixin {
  // State
  EmergencyContact? _contact;
  Position? _position;
  String _address = 'Fetching location...';
  bool _gpsReady = false;
  bool _contactReady = false;
  bool _locationReady = false;
  bool _sirenActive = false;
  bool _vibrationActive = false;
  bool _loadingPolice = true;
  bool _callActive = false;

  // Nearby police
  List<SearchResult> _policeStations = [];

  // Pulse animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Map
  MapLibreMapController? _mapCtrl;

  // Call state listener
  StreamSubscription<CallState>? _callStateSub;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _init();
  }

  Future<void> _init() async {
    // 1. Load contact instantly (SharedPreferences, <10ms)
    _contact = await EmergencyService.instance.getContact();
    if (mounted) setState(() => _contactReady = _contact != null);

    // 2. Start siren + vibration immediately
    EmergencyService.instance.startSiren().then((_) {
      if (mounted) setState(() => _sirenActive = EmergencyService.instance.isSirenActive);
    });
    EmergencyService.instance.startVibration().then((_) {
      if (mounted) setState(() => _vibrationActive = EmergencyService.instance.isVibrating);
    });

    // 3. Start call state listener + pre-request CALL_PHONE permission
    _listenToCallState();
    EmergencyService.instance.startCallStateListener();
    _requestCallPermission();

    // 4. Auto-call emergency contact if requested (after brief delay for UI)
    if (widget.autoCall && _contact != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _autoCallContact();
      });
    }

    // 5. Fetch GPS in background (non-blocking, UI shows immediately)
    _fetchLocationInBackground();
  }

  void _requestCallPermission() async {
    await EmergencyService.instance.requestCallPhonePermission();
  }

  Future<void> _fetchLocationInBackground() async {
    final position = await EmergencyService.instance.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _position = position;
      if (position != null) {
        _gpsReady = true;
        _locationReady = true;
      }
    });

    if (position != null) {
      _updateMapUserLocation(position);
      _findPolice();
      EmergencyService.instance
          .reverseGeocode(position.latitude, position.longitude)
          .then((addr) {
        if (mounted) setState(() => _address = addr);
      });
    }
    _startLocationStream();
  }

  void _listenToCallState() {
    _callStateSub = EmergencyService.instance.callStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _callActive = state == CallState.offhook;
      });
    });
  }

  Future<void> _autoCallContact() async {
    if (_contact == null) return;
    await EmergencyService.instance.callContactDirect(_contact!);
  }

  void _startLocationStream() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      _updateMapUserLocation(pos);
    });
  }

  void _updateMapUserLocation(Position pos) {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    ctrl.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude),
        15,
      ),
      duration: const Duration(milliseconds: 500),
    );
  }

  String? _cachedCityName;

  Future<void> _cacheCityName(double lat, double lng) async {
    if (_cachedCityName != null && _cachedCityName!.isNotEmpty) return;
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=10',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeSakhi/1.0'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        _cachedCityName = address?['city'] as String? ??
            address?['town'] as String? ??
            address?['village'] as String? ??
            address?['suburb'] as String? ??
            address?['county'] as String? ??
            '';
      }
    } catch (_) {}
  }

  Future<void> _findPolice() async {
    if (_position == null) return;
    final lat = _position!.latitude;
    final lng = _position!.longitude;

    await _cacheCityName(lat, lng);
    final city = _cachedCityName ?? '';

    debugPrint('[EmergencyMode] City: "$city"');

    List<SearchResult> results = [];

    // Use NearbySearchService — same 4-tier pipeline as Explore Safe Heaven
    try {
      final nearbySearch = NearbySearchService();
      results = await nearbySearch.searchCategory(
        SearchCategory.police,
        lat: lat,
        lng: lng,
        cityName: city,
      );
      debugPrint('[EmergencyMode] NearbySearchService results: ${results.length}');
    } catch (e) {
      debugPrint('[EmergencyMode] NearbySearchService error: $e');
    }

    // Filter out generic names
    results = results.where((r) => !SearchResult.isGenericName(r.name)).toList();

    if (mounted) {
      setState(() {
        _policeStations = results.take(5).toList();
        _loadingPolice = false;
      });
    }
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> _callContact() async {
    if (_contact == null) return;
    await EmergencyService.instance.callContactDirect(_contact!);
  }

  Future<void> _call112() async {
    await EmergencyService.instance.callNumberDirect('112');
  }

  Future<void> _shareLocation() async {
    if (_contact == null || _position == null) return;
    await EmergencyService.instance.shareLocationViaSms(
      _contact!,
      _position!.latitude,
      _position!.longitude,
    );
  }

  void _onPoliceStationTap(SearchResult station) {
    HapticFeedback.lightImpact();

    // Animate map to the station
    final ctrl = _mapCtrl;
    if (ctrl != null) {
      ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(station.position.latitude, station.position.longitude),
          16,
        ),
        duration: const Duration(milliseconds: 600),
      );
    }

    // Open place details sheet after camera settles
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PremiumBottomSheet(
          result: station,
          onNavigate: () {
            Navigator.pop(context);
            if (_position != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RouteSelectionScreen(
                    origin: ll.LatLng(_position!.latitude, _position!.longitude),
                    destination: station.position,
                    destinationName: station.name,
                  ),
                ),
              );
            }
          },
          onAddReview: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewFormScreen(
                  targetId: station.id,
                  targetName: station.name,
                  targetType: ReviewTargetType.place,
                  latitude: station.position.latitude,
                  longitude: station.position.longitude,
                ),
              ),
            );
          },
          onViewReviews: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityReviewsScreen(
                  targetId: station.id,
                  targetName: station.name,
                  isRoad: false,
                  latitude: station.position.latitude,
                  longitude: station.position.longitude,
                ),
              ),
            );
          },
          onShare: () async {
            final doc = await FirestoreService().getPlaceDoc(station.id);
            final data = doc.data() as Map<String, dynamic>?;
            if (!mounted) return;
            SafetyReportShare.share(
              name: station.name,
              latitude: station.position.latitude,
              longitude: station.position.longitude,
              aiScore: data?['score'] as int?,
              aiSummary: data?['summary'] as String?,
              reviewCount: data?['reviewCount'] as int? ?? 0,
            );
          },
          onClose: () => Navigator.pop(context),
        ),
      );
    });
  }

  Future<void> _imSafe() async {
    await EmergencyService.instance.stopAll();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _addContact() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmergencyContactScreen()),
    );
    if (result == true) {
      _contact = await EmergencyService.instance.getContact();
      if (mounted) setState(() => _contactReady = true);
    }
  }

  // ── Map ──────────────────────────────────────────────────────

  void _onMapCreated(MapLibreMapController ctrl) {
    _mapCtrl = ctrl;
    if (_position != null) {
      ctrl.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_position!.latitude, _position!.longitude),
          15,
        ),
      );
    }
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    EmergencyService.instance.stopCallStateListener();
    _pulseCtrl.dispose();
    EmergencyService.instance.stopAll();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showEndDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFB71C1C),
        body: Column(
          children: [
            SizedBox(height: safeTop),
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    _buildMapCard(),
                    const SizedBox(height: 12),
                    EmergencyStatusCard(
                      gpsReady: _gpsReady,
                      sirenActive: _sirenActive,
                      contactReady: _contactReady,
                      locationReady: _locationReady,
                      smsReady: _contactReady && _locationReady,
                      vibrationActive: _vibrationActive,
                    ),
                    const SizedBox(height: 12),
                    _buildLocationCard(),
                    const SizedBox(height: 12),
                    _buildActionButtons(),
                    const SizedBox(height: 12),
                    _buildPoliceCard(),
                    const SizedBox(height: 12),
                    _buildImSafeButton(safeBottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.emergency, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'EMERGENCY ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _showEndDialog,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          if (_callActive) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_in_talk, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'IN CALL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: CameraPosition(
              target: _position != null
                  ? LatLng(_position!.latitude, _position!.longitude)
                  : const LatLng(12.9716, 77.5946),
              zoom: 15,
            ),
            styleString:
                'https://api.maptiler.com/maps/streets-v2/style.json?key=${ApiKeys.mapTiler}',
            onMapCreated: _onMapCreated,
            myLocationEnabled: false,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            scrollGesturesEnabled: false,
            tiltGesturesEnabled: false,
            zoomGesturesEnabled: false,
            annotationOrder: const [],
          ),
          // User dot
          if (_position != null)
            Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _locationReady
                    ? Icons.check_circle
                    : Icons.location_searching,
                color:
                    _locationReady ? const Color(0xFF4CAF50) : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _locationReady ? 'Location Ready' : 'Location unavailable.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_position != null) ...[
            const SizedBox(height: 10),
            Text(
              _address,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Lat: ${_position!.latitude.toStringAsFixed(4)}, '
              'Lng: ${_position!.longitude.toStringAsFixed(4)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Accuracy: ${_position!.accuracy.round()}m',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Emergency calls and SMS still work without GPS.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasContact = _contact != null;
    final hasLocation = _position != null;

    return Column(
      children: [
        // Call Emergency Contact
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: hasContact && !_callActive ? _callContact : null,
            icon: Icon(
              _callActive ? Icons.phone_in_talk : Icons.phone,
              size: 22,
            ),
            label: Text(
              _callActive
                  ? 'In Call with ${_contact?.name ?? "Contact"}...'
                  : hasContact
                      ? 'Call ${_contact!.name}'
                      : 'No emergency contact configured',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _callActive
                  ? const Color(0xFF2E7D32)
                  : hasContact
                      ? const Color(0xFF4CAF50)
                      : Colors.white24,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  _callActive
                      ? const Color(0xFF2E7D32)
                      : Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor:
                  _callActive ? Colors.white70 : Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Call 112
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: !_callActive ? _call112 : null,
            icon: const Icon(Icons.local_phone, size: 22),
            label: const Text(
              'Call 112',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Share Live Location
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: (hasContact && hasLocation && !_callActive)
                ? _shareLocation
                : null,
            icon: const Icon(Icons.message, size: 22),
            label: Text(
              _callActive
                  ? 'Call in progress...'
                  : (hasContact && hasLocation)
                      ? 'Share Live Location'
                      : hasContact
                          ? 'Enable GPS to share location'
                          : 'Add contact & enable GPS',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: (hasContact && hasLocation && !_callActive)
                  ? AppColors.primaryBlue
                  : Colors.white24,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (!hasContact) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _addContact,
            child: Text(
              'Please add an Emergency Contact from your Profile.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPoliceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_police, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Nearby Police Stations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingPolice)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            )
          else if (_policeStations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No police stations found nearby',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            )
          else
            ...(_policeStations.map((s) => _buildPoliceRow(s))),
        ],
      ),
    );
  }

  Widget _buildPoliceRow(SearchResult station) {
    final userLoc = _position != null
        ? ll.LatLng(_position!.latitude, _position!.longitude)
        : null;
    final dist = userLoc != null
        ? const ll.Distance().distance(userLoc, station.position)
        : null;
    final distText = dist != null
        ? (dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km')
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onPoliceStationTap(station),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_police, color: Colors.white70, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (distText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          distText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.3), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImSafeButton(double safeBottom) {
    return Padding(
      padding: EdgeInsets.only(bottom: safeBottom + 16),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: FilledButton(
          onPressed: _imSafe,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 26),
              SizedBox(width: 10),
              Text(
                "I'm Safe",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEndDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Emergency?'),
        content: const Text(
            'This will stop the siren and vibration and return to the home screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _imSafe();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text("I'm Safe"),
          ),
        ],
      ),
    );
  }
}
