import 'dart:async';
import 'dart:math' show cos, sin, atan2, sqrt, pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../config/api_keys.dart';
import '../services/route_service.dart';
import '../theme/constants.dart';

class NavigationScreen extends StatefulWidget {
  final RouteData route;
  final String destinationName;
  final VehicleMode vehicle;
  final String routeColor;

  const NavigationScreen({
    super.key,
    required this.route,
    required this.destinationName,
    this.vehicle = VehicleMode.drive,
    this.routeColor = '#34A853',
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;

  ll.LatLng? _userPos;
  bool _firstFix = true;
  bool _styleLoaded = false;

  // Route progress
  int _nearestIdx = 0;
  double _remainingMeters = 0;
  double _traveledMeters = 0;
  bool _arrived = false;

  // Smooth route-bearing animation
  late final AnimationController _bearingAnim;
  Animation<double>? _bearingTween;
  double _displayBearing = 0;

  // Entrance fade
  late final AnimationController _fadeAnim;
  late final Animation<double> _fadeOpacity;

  // Camera state
  static const double _positionThresholdMeters = 3.0;
  ll.LatLng? _lastCameraPos;
  bool _userPanned = false;

  Color get _routeColorParsed =>
      Color(int.parse(widget.routeColor.replaceFirst('#', '0xFF')));

  Color get _routeColorDark {
    final hsl = HSLColor.fromColor(_routeColorParsed);
    return hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
  }

  @override
  void initState() {
    super.initState();
    _remainingMeters = widget.route.distanceMeters;
    _bearingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final tween = _bearingTween;
        if (tween == null || !mounted) return;
        setState(() => _displayBearing = tween.value % 360);
      });
    _fadeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeOpacity = CurvedAnimation(parent: _fadeAnim, curve: Curves.easeOut);
    _fadeAnim.forward();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bearingAnim.dispose();
    _fadeAnim.dispose();
    super.dispose();
  }

  // ── Location tracking ───────────────────────────────────────────

  void _startLocationTracking() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final newPos = ll.LatLng(pos.latitude, pos.longitude);

      setState(() {
        _userPos = newPos;
      });

      _updateProgress(newPos);
      final routeBearing = _routeBearingForIndex(_nearestIdx);
      _animateBearingTo(routeBearing);

      _updateAccuracyCircle(newPos, pos.accuracy);

      if (_firstFix) {
        _firstFix = false;
        _entranceCamera(newPos);
      } else if (!_userPanned) {
        _updateCamera(newPos);
      }
    });
  }

  // ── Bearing animation with shortest-path ───────────────────────

  void _animateBearingTo(double target) {
    if (_bearingAnim.isAnimating) _bearingAnim.stop();

    final current = _displayBearing;
    double diff = target - current;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    // Ignore tiny heading jitter (< 3°)
    if (diff.abs() < 3.0) return;

    final begin = current;
    final end = current + diff;
    _bearingTween = Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _bearingAnim, curve: Curves.easeInOut),
    );
    _bearingAnim.duration = const Duration(milliseconds: 200);
    _bearingAnim
      ..reset()
      ..forward().then((_) {
        if (mounted) setState(() => _displayBearing = target % 360);
      });
  }

  void _entranceCamera(ll.LatLng pos) {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    ctrl.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(pos.latitude, pos.longitude),
        17,
      ),
      duration: const Duration(milliseconds: 500),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || _mapCtrl == null) return;
      _mapCtrl!.animateCamera(
        CameraUpdate.tiltTo(45),
        duration: const Duration(milliseconds: 400),
      );
    });

    _lastCameraPos = pos;
  }

  // ── Progress calculation ────────────────────────────────────────

  void _updateProgress(ll.LatLng userPos) {
    final points = widget.route.points;
    if (points.isEmpty) return;

    double minDist = double.infinity;
    int nearest = _nearestIdx;

    final searchStart = (_nearestIdx - 20).clamp(0, points.length - 1);
    final searchEnd = (_nearestIdx + 40).clamp(0, points.length - 1);

    for (int i = searchStart; i <= searchEnd; i++) {
      final d = _haversine(userPos, points[i]);
      if (d < minDist) {
        minDist = d;
        nearest = i;
      }
    }

    if (nearest <= _nearestIdx - 15 && _nearestIdx > 0) {
      nearest = _nearestIdx;
    }

    double remaining = 0;
    for (int i = nearest; i < points.length - 1; i++) {
      remaining += _haversine(points[i], points[i + 1]);
    }

    final traveled = widget.route.distanceMeters - remaining;

    setState(() {
      _nearestIdx = nearest;
      _remainingMeters = remaining.clamp(0.0, widget.route.distanceMeters);
      _traveledMeters = traveled.clamp(0.0, widget.route.distanceMeters);
    });

    _updateProgressLayers();

    final destDist = _haversine(userPos, points.last);
    if (destDist < 30 && !_arrived) {
      setState(() => _arrived = true);
      HapticFeedback.heavyImpact();
      _showArrivalDialog();
    }
  }

  // ── Map layers ──────────────────────────────────────────────────

  void _onMapCreated(MapLibreMapController ctrl) {
    _mapCtrl = ctrl;
  }

  void _onStyleLoaded() {
    final ctrl = _mapCtrl;
    if (ctrl == null || _styleLoaded) return;
    _styleLoaded = true;
    _drawRoute(ctrl);
  }

  Future<void> _drawRoute(MapLibreMapController ctrl) async {
    final points = widget.route.points;
    final color = widget.routeColor;
    if (points.length < 2) return;

    final fullCoords = points.map((p) => [p.longitude, p.latitude]).toList();
    final fullGeoJson = {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': fullCoords,
      },
    };

    // White casing for map contrast.
    await ctrl.addGeoJsonSource('nav-route-casing', fullGeoJson);
    await ctrl.addLineLayer(
      'nav-route-casing',
      'nav-route-casing-line',
      LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: 10.0,
        lineOpacity: 0.92,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // Traveled portion (darker, lower opacity)
    await ctrl.addGeoJsonSource('nav-route-traveled', {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [points.first.longitude, points.first.latitude],
          [points.first.longitude, points.first.latitude],
        ],
      },
    });
    await ctrl.addLineLayer(
      'nav-route-traveled',
      'nav-route-traveled-line',
      LineLayerProperties(
        lineColor: _colorToHex(_routeColorDark),
        lineWidth: 7.0,
        lineOpacity: 0.34,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // Remaining portion (full color, on top)
    await ctrl.addGeoJsonSource('nav-route-remaining', fullGeoJson);
    await ctrl.addLineLayer(
      'nav-route-remaining',
      'nav-route-remaining-line',
      LineLayerProperties(
        lineColor: color,
        lineWidth: 7.5,
        lineOpacity: 1.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // Destination marker
    final dest = points.last;
    await ctrl.addGeoJsonSource('nav-dest', {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [dest.longitude, dest.latitude],
      },
    });
    await ctrl.addCircleLayer('nav-dest', 'nav-dest-circle',
      CircleLayerProperties(
        circleRadius: 12,
        circleColor: '#EA4335',
        circleStrokeWidth: 3,
        circleStrokeColor: '#FFFFFF',
      ),
    );
    await ctrl.addSymbolLayer('nav-dest', 'nav-dest-label',
      SymbolLayerProperties(
        textField: widget.destinationName,
        textSize: 12,
        textColor: '#D32F2F',
        textFont: ['DIN Pro Medium', 'Arial Unicode MS Regular'],
        textOffset: [0, 2.2],
        textAnchor: 'top',
        textAllowOverlap: true,
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.5,
      ),
    );

    // GPS accuracy circle
    await ctrl.addGeoJsonSource('nav-accuracy', {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [0, 0],
      },
    });
    await ctrl.addCircleLayer('nav-accuracy', 'nav-accuracy-circle',
      CircleLayerProperties(
        circleRadius: 0,
        circleColor: '#4285F4',
        circleOpacity: 20,
        circleStrokeWidth: 1,
        circleStrokeColor: '#4285F4',
        circleStrokeOpacity: 30,
        circlePitchAlignment: 'map',
      ),
    );
  }

  Future<void> _updateAccuracyCircle(ll.LatLng pos, double accuracy) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    try {
      final radius = (accuracy / 2.0).clamp(20.0, 200.0);
      await ctrl.setGeoJsonSource('nav-accuracy', {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [pos.longitude, pos.latitude],
        },
        'properties': {
          'radius': radius,
        },
      });
    } catch (_) {}
  }

  Future<void> _updateProgressLayers() async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    final points = widget.route.points;
    if (points.length < 2) return;
    if (_nearestIdx >= points.length) return;

    final traveledCoords = points
        .sublist(0, _nearestIdx + 1)
        .map((p) => [p.longitude, p.latitude])
        .toList();
    if (traveledCoords.length == 1) {
      traveledCoords.add(traveledCoords.first);
    }
    try {
      await ctrl.setGeoJsonSource('nav-route-traveled', {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': traveledCoords,
        },
      });
    } catch (_) {}

    final remainingCoords = points
        .sublist(_nearestIdx)
        .map((p) => [p.longitude, p.latitude])
        .toList();
    if (remainingCoords.length == 1) {
      remainingCoords.insert(0, traveledCoords.last);
    }
    try {
      await ctrl.setGeoJsonSource('nav-route-remaining', {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': remainingCoords,
        },
      });
    } catch (_) {}
  }

  // ── Camera with thresholds ─────────────────────────────────────

  void _updateCamera(ll.LatLng pos) {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    bool shouldRecenter = false;
    if (_lastCameraPos == null) {
      shouldRecenter = true;
    } else {
      final distMoved = _haversine(_lastCameraPos!, pos);
      if (distMoved > _positionThresholdMeters) {
        shouldRecenter = true;
      }
    }

    if (shouldRecenter) {
      ctrl.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(pos.latitude, pos.longitude),
          17,
        ),
        duration: const Duration(milliseconds: 250),
      );
      _lastCameraPos = pos;
    }
  }

  void _recenterCamera() {
    if (_userPos == null) return;
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    ctrl.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(_userPos!.latitude, _userPos!.longitude),
        17,
      ),
      duration: const Duration(milliseconds: 300),
    );

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || _mapCtrl == null) return;
      _mapCtrl!.animateCamera(
        CameraUpdate.tiltTo(45),
        duration: const Duration(milliseconds: 200),
      );
    });

    setState(() {
      _userPanned = false;
      _lastCameraPos = _userPos;
    });
  }

  // ── Arrival ─────────────────────────────────────────────────────

  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF34A853), size: 28),
            SizedBox(width: 10),
            Text('You\'ve Arrived!'),
          ],
        ),
        content: Text(
          'You have reached ${widget.destinationName}',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static double _haversine(ll.LatLng a, ll.LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  static double _computeBearing(ll.LatLng from, ll.LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLng = (to.longitude - from.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _routeBearingForIndex(int nearestIdx) {
    final points = widget.route.points;
    if (points.length < 2) return _displayBearing;

    final fromIdx = nearestIdx.clamp(0, points.length - 2);
    var toIdx = (fromIdx + 1).clamp(1, points.length - 1);

    // Look slightly ahead so the arrow points through gentle bends instead of
    // twitching on dense route points.
    for (var i = fromIdx + 1; i < points.length; i++) {
      toIdx = i;
      if (_haversine(points[fromIdx], points[i]) > 18) break;
    }

    return _computeBearing(points[fromIdx], points[toIdx]);
  }

  static String _colorToHex(Color c) {
    return '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final total = seconds.round();
    final mins = total ~/ 60;
    final secs = total % 60;
    if (mins < 60) return '${mins}m ${secs}s';
    final hrs = mins ~/ 60;
    final remainMins = mins % 60;
    return '${hrs}h ${remainMins}m';
  }

  String _formatEta(double seconds) {
    final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
    final h = arrival.hour;
    final m = arrival.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $period';
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;

    final speedMps = widget.vehicle.speedKmh * 1000 / 3600;
    final double etaSeconds = speedMps > 0 ? _remainingMeters / speedMps : 0.0;
    final double progress = widget.route.distanceMeters > 0
        ? (_traveledMeters / widget.route.distanceMeters).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Map
          MapLibreMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                widget.route.points.first.latitude,
                widget.route.points.first.longitude,
              ),
              zoom: 15,
            ),
            styleString:
                'https://api.maptiler.com/maps/streets-v2/style.json?key=${ApiKeys.mapTiler}',
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: false,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            scrollGesturesEnabled: false,
            tiltGesturesEnabled: false,
            zoomGesturesEnabled: false,
            annotationOrder: const [],
          ),

          // Navigation arrow — centered on screen
          FadeTransition(
            opacity: _fadeOpacity,
            child: Center(
              child: Transform.rotate(
                angle: _displayBearing * pi / 180,
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _NavigationArrowPainter(
                    color: _routeColorParsed,
                  ),
                ),
              ),
            ),
          ),

          // Top instruction card
          Positioned(
            top: safeTop + 8,
            left: 16,
            right: 16,
            child: FadeTransition(
              opacity: _fadeOpacity,
              child: _buildInstructionCard(),
            ),
          ),

          // Recenter button (shows when user has panned)
          if (_userPanned)
            Positioned(
              bottom: 240,
              right: 16,
              child: FadeTransition(
                opacity: _fadeOpacity,
                child: _buildRecenterButton(),
              ),
            ),

          // Bottom HUD
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeOpacity,
              child: _buildBottomHud(etaSeconds, progress),
            ),
          ),
        ],
      ),
    );
  }

  // ── Instruction card ────────────────────────────────────────────

  Widget _buildInstructionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: () => _showEndDialog(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 12),
          // Instruction
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded,
                        size: 18, color: _routeColorParsed),
                    const SizedBox(width: 4),
                    Text(
                      'Continue Straight',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _routeColorParsed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Destination: ${widget.destinationName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatDistance(_remainingMeters)} remaining',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
          // Mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.vehicle.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recenter button ─────────────────────────────────────────────

  Widget _buildRecenterButton() {
    return GestureDetector(
      onTap: _recenterCamera,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location,
          size: 22,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }

  // ── Bottom HUD ──────────────────────────────────────────────────

  Widget _buildBottomHud(double etaSeconds, double progress) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, safeBottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_routeColorParsed),
            ),
          ),
          const SizedBox(height: 14),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(
                  Icons.access_time_rounded, _formatDuration(etaSeconds), 'ETA'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _buildStat(Icons.straighten, _formatDistance(_remainingMeters),
                  'Distance'),
              Container(width: 1, height: 32, color: Colors.grey.shade200),
              _buildStat(
                  Icons.flag_rounded, _formatEta(etaSeconds), 'Arrival'),
            ],
          ),
          const SizedBox(height: 14),

          // End Journey button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _showEndDialog,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop_rounded, size: 22),
                  SizedBox(width: 8),
                  Text('End Journey',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  void _showEndDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Navigation?'),
        content: const Text('Are you sure you want to end this journey?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorRed,
            ),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}

// ── Navigation arrow painter ──────────────────────────────────

class _NavigationArrowPainter extends CustomPainter {
  final Color color;

  _NavigationArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _arrowPath(size);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path.shift(const Offset(1.2, 2.2)), shadowPaint);

    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, outlinePaint);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, highlightPaint);
  }

  Path _arrowPath(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.33;
    final h = size.height * 0.42;

    return Path()
      ..moveTo(cx, cy - h)
      ..lineTo(cx + w, cy + h * 0.55)
      ..quadraticBezierTo(cx, cy + h * 0.25, cx - w, cy + h * 0.55)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _NavigationArrowPainter oldDelegate) =>
      color != oldDelegate.color;
}
