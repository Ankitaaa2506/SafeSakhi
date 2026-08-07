import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../config/api_keys.dart';
import '../services/route_service.dart';
import '../services/route_generation_service.dart';
import '../services/zone_cache.dart';
import '../theme/constants.dart';
import 'navigation_screen.dart';

class _NavOption {
  final RouteData route;
  final int colorIndex;
  final String label;
  final String timeDeltaText;
  final int zonesAvoided;
  final int zonesCrossed;
  final List<SafetyZone> warningZones;

  const _NavOption({
    required this.route,
    required this.colorIndex,
    required this.label,
    required this.timeDeltaText,
    this.zonesAvoided = 0,
    this.zonesCrossed = 0,
    this.warningZones = const [],
  });
}

class RouteSelectionScreen extends StatefulWidget {
  final ll.LatLng origin;
  final ll.LatLng destination;
  final String? destinationName;

  const RouteSelectionScreen({
    super.key,
    required this.origin,
    required this.destination,
    this.destinationName,
  });

  @override
  State<RouteSelectionScreen> createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen>
    with SingleTickerProviderStateMixin {
  final Completer<MapLibreMapController> _mapCompleter = Completer();
  MapLibreMapController? _mapCtrl;

  List<_NavOption> _options = [];
  int _selected = 0;
  VehicleMode _vehicle = VehicleMode.drive;
  bool _loading = true;
  bool _reloading = false;
  String? _error;

  bool _styleLoaded = false;
  bool _routesReady = false;
  bool _drawingRoutes = false;
  bool _layersReady = false;

  late final AnimationController _shimmerCtrl;

  static const _routeColors = ['#34A853', '#FBBC05', '#EA4335'];
  static const _routeSourcePrefix = 'route-src';
  static const _routeLayerPrefix = 'route-line';
  static const _hitLayerPrefix = 'route-hit';
  static const _markerSourcePrefix = 'marker-src';
  static const _markerLayerPrefix = 'marker';

  Color _colorFor(int idx) =>
      Color(int.parse(_routeColors[idx].replaceFirst('#', '0xFF')));

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadRoutes();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  // ── Route loading ──────────────────────────────────────────────────

  Future<void> _loadRoutes() async {
    final sw = Stopwatch()..start();
    try {
      await ZoneCache.instance.warmUp();

      final engine = RouteGenerationService();
      final generated = await engine.generateRoutes(
        origin: widget.origin,
        destination: widget.destination,
        vehicle: _vehicle,
      );
      sw.stop();

      if (generated.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No routes found';
            _loading = false;
            _reloading = false;
          });
        }
        return;
      }

      final options = generated
          .map((gr) => _NavOption(
                route: gr.route,
                colorIndex: gr.colorIndex,
                label: gr.label,
                timeDeltaText: gr.timeDeltaText,
                zonesAvoided: gr.zonesAvoided,
                zonesCrossed: gr.zonesCrossed,
                warningZones: gr.warningZones,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _options = options;
          _loading = false;
          _reloading = false;
          _selected = 0;
        });
      }

      _routesReady = true;
      if (_styleLoaded) _drawRoutes();

      developer.log('Screen: routes loaded in ${sw.elapsedMilliseconds}ms (${options.length} options)', name: 'SafeSakhi.Screen');
    } catch (e) {
      developer.log('Screen: load error — $e', name: 'SafeSakhi.Screen');
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
          _reloading = false;
        });
      }
    }
  }

  void _reloadRoutes() {
    setState(() {
      _reloading = true;
      _options = [];
      _routesReady = false;
      _layersReady = false;
    });
    _loadRoutes();
  }

  // ── Instant mode switch ──────────────────────────────────────────────

  void _onVehicleChanged(VehicleMode mode) {
    if (mode == _vehicle) return;
    setState(() => _vehicle = mode);

    if (_options.isNotEmpty) {
      _drawRoutes();
    } else {
      _reloadRoutes();
    }
  }

  // ── Map layer management ───────────────────────────────────────────

  Future<void> _drawRoutes() async {
    if (_drawingRoutes || _mapCtrl == null || _options.isEmpty) return;
    _drawingRoutes = true;

    final ctrl = _mapCtrl!;
    await _clearLayers(ctrl);

    // ── Phase 6: Rendering priority ──
    // Draw inactive routes first (thinner, lower opacity), active last (thicker, full opacity)
    final drawOrder = <int>[];
    for (int i = 0; i < _options.length; i++) {
      if (i != _selected) drawOrder.add(i);
    }
    drawOrder.add(_selected);

    for (final i in drawOrder) {
      final opt = _options[i];
      final isActive = i == _selected;

      final geoJson = {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': opt.route.points
              .map((p) => [p.longitude, p.latitude])
              .toList(),
        },
      };

      await ctrl.addGeoJsonSource('$_routeSourcePrefix-$i', geoJson);
      await ctrl.addLineLayer(
        '$_routeSourcePrefix-$i',
        '$_routeLayerPrefix-$i',
        LineLayerProperties(
          lineColor: _routeColors[opt.colorIndex],
          lineWidth: isActive ? 5.5 : 3.0,
          lineOpacity: isActive ? 1.0 : 0.35,
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );

      // Invisible tap hit area
      await ctrl.addGeoJsonSource('$_routeSourcePrefix-hit-$i', geoJson);
      await ctrl.addLineLayer(
        '$_routeSourcePrefix-hit-$i',
        '$_hitLayerPrefix-$i',
        LineLayerProperties(
          lineColor: '#000000',
          lineWidth: 28.0,
          lineOpacity: 0.001,
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );
    }

    await _addCircleMarker(ctrl, 'start',
        lat: widget.origin.latitude,
        lng: widget.origin.longitude,
        color: '#34A853',
        radius: 9,
        strokeColor: '#FFFFFF',
        strokeWidth: 3);

    await _addCircleMarker(ctrl, 'dest',
        lat: widget.destination.latitude,
        lng: widget.destination.longitude,
        color: '#EA4335',
        radius: 11,
        strokeColor: '#FFFFFF',
        strokeWidth: 3);

    _layersReady = true;
    _drawingRoutes = false;
    _fitBounds(ctrl);
  }

  Future<void> _clearLayers(MapLibreMapController ctrl) async {
    for (int i = 0; i < 3; i++) {
      try { await ctrl.removeLayer('$_routeLayerPrefix-$i'); } catch (_) {}
      try { await ctrl.removeSource('$_routeSourcePrefix-$i'); } catch (_) {}
      try { await ctrl.removeLayer('$_hitLayerPrefix-$i'); } catch (_) {}
      try { await ctrl.removeSource('$_routeSourcePrefix-hit-$i'); } catch (_) {}
    }
    for (final id in ['start', 'dest']) {
      try { await ctrl.removeLayer('$_markerLayerPrefix-$id'); } catch (_) {}
      try { await ctrl.removeSource('$_markerSourcePrefix-$id'); } catch (_) {}
    }
    _layersReady = false;
  }

  Future<void> _addCircleMarker(
    MapLibreMapController ctrl,
    String id, {
    required double lat,
    required double lng,
    required String color,
    required double radius,
    required String strokeColor,
    required double strokeWidth,
  }) async {
    final geoJson = {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
    };
    await ctrl.addGeoJsonSource('$_markerSourcePrefix-$id', geoJson);
    await ctrl.addCircleLayer(
      '$_markerSourcePrefix-$id',
      '$_markerLayerPrefix-$id',
      CircleLayerProperties(
        circleRadius: radius,
        circleColor: color,
        circleStrokeWidth: strokeWidth,
        circleStrokeColor: strokeColor,
      ),
    );
  }

  void _fitBounds(MapLibreMapController ctrl) {
    if (_options.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final opt in _options) {
      for (final p in opt.route.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    ctrl.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: MediaQuery.of(context).padding.top + 80,
        right: 40,
        bottom: MediaQuery.of(context).size.height * 0.44,
      ),
    );
  }

  // ── Interaction ────────────────────────────────────────────────────

  void _selectOption(int idx) {
    if (idx == _selected) return;
    setState(() => _selected = idx);
    _drawRoutes();
  }

  void _onMapTap(Point<double> point, LatLng latLng) async {
    final ctrl = _mapCtrl;
    if (ctrl == null || !_layersReady) return;

    final hitIds = List.generate(_options.length, (i) => '$_hitLayerPrefix-$i');
    final features = await ctrl.queryRenderedFeatures(point, hitIds, null);
    if (features.isEmpty) return;

    final layer = features.first['layer'] as Map<String, dynamic>?;
    final layerId = layer?['id'] as String? ?? '';
    final parts = layerId.split('-');
    final idx = int.tryParse(parts.last);
    if (idx != null && idx < _options.length) {
      _selectOption(idx);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                (widget.origin.latitude + widget.destination.latitude) / 2,
                (widget.origin.longitude + widget.destination.longitude) / 2,
              ),
              zoom: 12,
            ),
            styleString:
                'https://api.maptiler.com/maps/streets-v2/style.json?key=${ApiKeys.mapTiler}',
            annotationOrder: const [],
            compassEnabled: false,
            onMapCreated: (ctrl) {
              if (!_mapCompleter.isCompleted) _mapCompleter.complete(ctrl);
              _mapCtrl = ctrl;
            },
            onStyleLoadedCallback: () {
              _styleLoaded = true;
              if (_routesReady) _drawRoutes();
            },
            onMapClick: _onMapTap,
          ),

          if (!_loading && _options.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: _buildToolbar(),
            ),

          if (_loading) _buildLoadingOverlay(),
          if (_reloading && !_loading) _buildReloadBadge(),
          if (_error != null) _buildErrorOverlay(),

          if (!_loading && _options.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomSheet(),
            ),
        ],
      ),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_back, size: 20, color: Colors.grey.shade700),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Colors.grey.shade200,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _transportChip(Icons.directions_car, 'Drive', VehicleMode.drive),
                _transportChip(Icons.directions_walk, 'Walk', VehicleMode.walk),
                _transportChip(Icons.directions_bike, 'Cycle', VehicleMode.cycle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transportChip(IconData icon, String label, VehicleMode mode) {
    final active = _vehicle == mode;
    return GestureDetector(
      onTap: () => _onVehicleChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: active ? Colors.white : Colors.grey.shade500),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheet ───────────────────────────────────────────────────

  Widget _buildBottomSheet() {
    final opt = _options[_selected];
    final color = _colorFor(opt.colorIndex);
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, safeBottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          _buildRouteTabs(),

          const SizedBox(height: 14),

          _buildDetailsRow(opt, color),

          if (opt.warningZones.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildWarningBanner(opt),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NavigationScreen(
                      route: opt.route,
                      destinationName: widget.destinationName ?? 'Destination',
                      vehicle: _vehicle,
                      routeColor: _routeColors[opt.colorIndex],
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Start Navigation',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Time delta of option [idx] vs. the currently fastest option, computed
  /// from the live [VehicleMode] so it always matches the durations shown.
  String _timeDeltaTextFor(int idx) {
    var fastestSecs = double.infinity;
    for (final opt in _options) {
      final secs = opt.route.durationSecondsFor(_vehicle);
      if (secs < fastestSecs) fastestSecs = secs;
    }
    final thisSecs = _options[idx].route.durationSecondsFor(_vehicle);
    if (thisSecs <= fastestSecs + 5) return 'Fastest';
    return '+${_formatDeltaSeconds(thisSecs - fastestSecs)}';
  }

  static String _formatDeltaSeconds(double seconds) {
    final total = seconds.round();
    final mins = total ~/ 60;
    final secs = total % 60;
    if (mins == 0) return '${secs}s';
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  Widget _buildRouteTabs() {
    return Row(
      children: List.generate(_options.length, (i) {
        final opt = _options[i];
        final deltaText = _timeDeltaTextFor(i);
        final isSelected = i == _selected;
        final color = _colorFor(opt.colorIndex);
        return Expanded(
          child: GestureDetector(
            onTap: () => _selectOption(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 5,
                right: i == _options.length - 1 ? 0 : 5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.10)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? color : Colors.grey.shade200,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    opt.route.durationTextFor(_vehicle),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.grey.shade800
                          : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: deltaText == 'Fastest'
                          ? const Color(0xFF34A853).withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      deltaText,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: deltaText == 'Fastest'
                            ? const Color(0xFF34A853)
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDetailsRow(_NavOption opt, Color color) {
    final durationText = opt.route.durationTextFor(_vehicle);
    final etaSecs = opt.route.durationSecondsFor(_vehicle);
    final arrival = DateTime.now().add(Duration(seconds: etaSecs.round()));
    final h = arrival.hour;
    final m = arrival.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final etaText = '$h12:$m $period';

    // Safety badge color based on risk score (lower = safer)
    final riskScore = opt.zonesCrossed;
    final safetyBadgeColor = riskScore == 0
        ? const Color(0xFF34A853)
        : riskScore <= 2
            ? const Color(0xFFFBBC05)
            : const Color(0xFFEA4335);
    final safetyLabel = riskScore == 0
        ? 'Very Safe'
        : riskScore <= 2
            ? 'Moderate'
            : 'Caution';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              opt.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: safetyBadgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    riskScore == 0
                        ? Icons.shield_rounded
                        : riskScore <= 2
                            ? Icons.info_outline
                            : Icons.warning_amber_rounded,
                    size: 10,
                    color: safetyBadgeColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    safetyLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: safetyBadgeColor,
                    ),
                  ),
                ],
              ),
            ),
            if (opt.zonesAvoided > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF34A853).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${opt.zonesAvoided} avoided',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF34A853),
                  ),
                ),
              ),
            ],
            const Spacer(),
            _detailChip(Icons.straighten, opt.route.distanceText),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              'Arrive at $etaText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const Spacer(),
            Text(
              durationText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detailChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(_NavOption opt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Color(0xFFF57C00)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${opt.zonesCrossed} safety concern${opt.zonesCrossed > 1 ? 's' : ''} on this route',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE65100),
                  ),
                ),
                if (opt.warningZones.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      opt.warningZones
                          .take(2)
                          .map((z) => z.roadName ?? 'Unmarked area')
                          .join(' • '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading / Error overlays ───────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Finding safe routes…',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Analysing community safety data',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReloadBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Updating routes…', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppStyles.elevatedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              'Could not load routes',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _loadRoutes();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue),
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
