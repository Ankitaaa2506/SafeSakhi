import 'dart:async';
import 'dart:math' show sin, cos, atan2, sqrt, pi;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import '../models/emergency_contact.dart';

enum CallState { idle, ringing, offhook, unknown }

class EmergencyService {
  EmergencyService._();
  static final EmergencyService instance = EmergencyService._();

  // Platform channels
  static const _methodChannel = MethodChannel('com.safesakhi/calls');
  static const _eventChannel = EventChannel('com.safesakhi/call_state');

  AudioPlayer? _sirenPlayer;
  bool _sirenPlaying = false;
  bool _vibrating = false;
  bool _sirenWasPlayingBeforeCall = false;
  bool _vibrationWasActiveBeforeCall = false;

  // Call state
  StreamSubscription? _callStateSub;
  final StreamController<CallState> _callStateController =
      StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;
  CallState _currentCallState = CallState.idle;
  CallState get currentCallState => _currentCallState;

  // ── Contact ────────────────────────────────────────────────────

  Future<EmergencyContact?> getContact() => EmergencyContact.load();
  Future<void> saveContact(EmergencyContact c) => c.save();
  Future<void> deleteContact() => EmergencyContact.delete();

  // ── Location ───────────────────────────────────────────────────

  Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      debugPrint('[Emergency] Location error: $e');
      return null;
    }
  }

  String generateMapsLink(double lat, double lng) =>
      'https://maps.google.com/?q=$lat,$lng';

  String generateEmergencyMessage(double lat, double lng) {
    final mapsLink = generateMapsLink(lat, lng);
    return '🚨 EMERGENCY!\n'
        'I need immediate help.\n\n'
        'My current location:\n'
        '$mapsLink\n\n'
        'Sent from SafeSakhi.';
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18',
      );
      final resp = await http
          .get(url, headers: {'User-Agent': 'SafeSakhi/1.0'})
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['display_name'] as String? ?? 'Unknown location';
      }
    } catch (_) {}
    return 'Unknown location';
  }

  // ── Siren ──────────────────────────────────────────────────────

  Future<void> startSiren() async {
    if (_sirenPlaying) return;
    try {
      _sirenPlayer = AudioPlayer();
      await _sirenPlayer!.setReleaseMode(ReleaseMode.loop);
      await _sirenPlayer!.setVolume(1.0);
      await _sirenPlayer!.play(AssetSource('siren.mp3'));
      _sirenPlaying = true;
    } catch (e) {
      debugPrint('[Emergency] Siren error: $e');
    }
  }

  Future<void> stopSiren() async {
    try {
      await _sirenPlayer?.stop();
      await _sirenPlayer?.dispose();
      _sirenPlayer = null;
      _sirenPlaying = false;
    } catch (_) {}
  }

  Future<void> pauseSiren() async {
    if (!_sirenPlaying) return;
    _sirenWasPlayingBeforeCall = true;
    try {
      await _sirenPlayer?.pause();
    } catch (_) {}
  }

  Future<void> resumeSirenIfNeeded() async {
    if (!_sirenWasPlayingBeforeCall) return;
    _sirenWasPlayingBeforeCall = false;
    try {
      await _sirenPlayer?.resume();
    } catch (_) {}
  }

  bool get isSirenActive => _sirenPlaying;

  // ── Vibration ──────────────────────────────────────────────────

  Future<void> startVibration() async {
    if (_vibrating) return;
    try {
      if (await Vibration.hasVibrator()) {
        _vibrating = true;
        Vibration.vibrate(
          pattern: [0, 800, 200, 800, 200, 800],
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
    } catch (e) {
      debugPrint('[Emergency] Vibration error: $e');
    }
  }

  Future<void> stopVibration() async {
    try {
      await Vibration.cancel();
      _vibrating = false;
    } catch (_) {}
  }

  void pauseVibration() {
    if (!_vibrating) return;
    _vibrationWasActiveBeforeCall = true;
    stopVibration();
  }

  void resumeVibrationIfNeeded() {
    if (!_vibrationWasActiveBeforeCall) return;
    _vibrationWasActiveBeforeCall = false;
    startVibration();
  }

  bool get isVibrating => _vibrating;

  // ── Phone call (direct via ACTION_CALL) ────────────────────────

  static String _cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  }

  Future<bool> _requestCallPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('requestCallPhonePermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Public method to pre-request CALL_PHONE permission.
  Future<bool> requestCallPhonePermission() => _requestCallPermission();

  /// Make a direct call using ACTION_CALL (no dialer).
  /// Falls back to ACTION_DIAL if permission denied.
  Future<bool> callContactDirect(EmergencyContact contact) async {
    final phone = _cleanPhone(contact.phone);
    return _makeDirectCall(phone);
  }

  Future<bool> callNumberDirect(String number) async {
    final phone = _cleanPhone(number);
    return _makeDirectCall(phone);
  }

  Future<bool> _makeDirectCall(String phone) async {
    try {
      final hasPermission = await _requestCallPermission();
      if (hasPermission) {
        final result = await _methodChannel.invokeMethod<bool>(
          'makeDirectCall',
          {'number': phone},
        );
        return result ?? false;
      } else {
        // Fallback to dialer
        final uri = Uri.parse('tel:$phone');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('[Emergency] Direct call error: $e');
      return false;
    }
  }

  // ── Legacy call (opens dialer) ────────────────────────────────

  Future<bool> callContact(EmergencyContact contact) async {
    try {
      final phone = _cleanPhone(contact.phone);
      final uri = Uri.parse('tel:$phone');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      debugPrint('[Emergency] Call error: $e');
      return false;
    }
  }

  Future<bool> callNumber(String number) async {
    try {
      final phone = _cleanPhone(number);
      final uri = Uri.parse('tel:$phone');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      debugPrint('[Emergency] Call number error: $e');
      return false;
    }
  }

  // ── SMS ────────────────────────────────────────────────────────

  Future<bool> shareLocationViaSms(
      EmergencyContact contact, double lat, double lng) async {
    try {
      final phone = _cleanPhone(contact.phone);
      final message = generateEmergencyMessage(lat, lng);
      final uri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': message},
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      debugPrint('[Emergency] SMS error: $e');
      return false;
    }
  }

  // ── Call state listener ────────────────────────────────────────

  bool _wasInCall = false;

  void startCallStateListener() {
    _callStateSub?.cancel();
    _methodChannel.invokeMethod('startCallStateListener');
    _callStateSub = _eventChannel.receiveBroadcastStream().listen((event) {
      final stateStr = event as String;
      final state = _parseCallState(stateStr);
      _currentCallState = state;
      _callStateController.add(state);

      if (state == CallState.offhook) {
        _wasInCall = true;
        pauseSiren();
        pauseVibration();
        _enableSpeaker();
      } else if (state == CallState.idle && _wasInCall) {
        _wasInCall = false;
        resumeSirenIfNeeded();
        resumeVibrationIfNeeded();
        _disableSpeaker();
        // Auto-return to app after call ends
        Future.delayed(const Duration(milliseconds: 500), () {
          bringAppToForeground();
        });
      }
    });
  }

  void stopCallStateListener() {
    _callStateSub?.cancel();
    _callStateSub = null;
    _methodChannel.invokeMethod('stopCallStateListener');
  }

  CallState _parseCallState(String state) {
    switch (state) {
      case 'IDLE':
        return CallState.idle;
      case 'RINGING':
        return CallState.ringing;
      case 'OFFHOOK':
        return CallState.offhook;
      default:
        return CallState.unknown;
    }
  }

  // ── Speaker ────────────────────────────────────────────────────

  Future<void> _enableSpeaker() async {
    try {
      await _methodChannel.invokeMethod('setSpeakerphone', {'enabled': true});
    } catch (_) {}
  }

  Future<void> _disableSpeaker() async {
    try {
      await _methodChannel.invokeMethod('setSpeakerphone', {'enabled': false});
    } catch (_) {}
  }

  Future<void> bringAppToForeground() async {
    try {
      await _methodChannel.invokeMethod('bringAppToForeground');
    } catch (_) {}
  }

  // ── Nearby Police (with fallback) ─────────────────────────────

  Future<List<PoliceStation>> findNearbyPolice(ll.LatLng center) async {
    // Try multiple Overpass tag combinations with increasing radius
    final tagSets = [
      ['police'],
      ['police', 'police_station'],
      ['police', 'police_station', 'law_enforcement'],
      ['police', 'police_station', 'law_enforcement', 'justice'],
    ];
    final radii = [2000.0, 5000.0, 10000.0, 15000.0];

    for (final radius in radii) {
      for (final tags in tagSets) {
        try {
          final results = await _searchPoliceWithTags(
            center: center,
            tags: tags,
            radiusMeters: radius,
          );
          if (results.isNotEmpty) {
            results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
            return results;
          }
        } catch (_) {}
      }
    }

    // Final fallback: try searching by name-based Overpass query
    try {
      return await _searchPoliceByNameFallback(center);
    } catch (_) {}

    return [];
  }

  Future<List<PoliceStation>> _searchPoliceWithTags({
    required ll.LatLng center,
    required List<String> tags,
    required double radiusMeters,
  }) async {
    final tagFilters = tags
        .map((tag) =>
            'node["amenity"="$tag"](around:$radiusMeters,${center.latitude},${center.longitude});'
            'way["amenity"="$tag"](around:$radiusMeters,${center.latitude},${center.longitude});')
        .join('\n  ');

    // Also search office=law_enforcement and place names containing "police"
    final extraFilters = '''
node["office"="law_enforcement"](around:$radiusMeters,${center.latitude},${center.longitude});
way["office"="law_enforcement"](around:$radiusMeters,${center.latitude},${center.longitude});
node["amenity"="justice"](around:$radiusMeters,${center.latitude},${center.longitude});
''';

    final query = '''
[out:json][timeout:10];
(
  $tagFilters
  $extraFilters
);
out center tags;''';

    try {
      final response = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      return elements
          .where((e) => e['tags'] != null && (e['tags'] as Map).isNotEmpty)
          .map((e) {
        final tagsMap = e['tags'] as Map<String, dynamic>;
        final name = tagsMap['name'] as String? ??
            tagsMap['name:en'] as String? ??
            tagsMap['name:hi'] as String? ??
            'Police Station';
        final lat = (e['lat'] as num?)?.toDouble() ??
            (e['center'] != null
                ? (e['center']['lat'] as num?)?.toDouble()
                : null) ??
            0;
        final lng = (e['lon'] as num?)?.toDouble() ??
            (e['center'] != null
                ? (e['center']['lon'] as num?)?.toDouble()
                : null) ??
            0;
        final pos = ll.LatLng(lat, lng);
        final dist = _haversine(center, pos);
        return PoliceStation(
          name: name,
          position: pos,
          distanceMeters: dist,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PoliceStation>> _searchPoliceByNameFallback(ll.LatLng center) async {
    // Search for any node/way with "police" in the name within 15km
    final query = '''
[out:json][timeout:10];
(
  node["name"~"police","i"](around:15000,${center.latitude},${center.longitude});
  way["name"~"police","i"](around:15000,${center.latitude},${center.longitude});
  node["name"~"thana","i"](around:15000,${center.latitude},${center.longitude});
  way["name"~"thana","i"](around:15000,${center.latitude},${center.longitude});
);
out center tags;''';

    try {
      final response = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      return elements
          .where((e) => e['tags'] != null && (e['tags'] as Map).isNotEmpty)
          .map((e) {
        final tagsMap = e['tags'] as Map<String, dynamic>;
        final name = tagsMap['name'] as String? ??
            tagsMap['name:en'] as String? ??
            tagsMap['name:hi'] as String? ??
            'Police Station';
        final lat = (e['lat'] as num?)?.toDouble() ??
            (e['center'] != null
                ? (e['center']['lat'] as num?)?.toDouble()
                : null) ??
            0;
        final lng = (e['lon'] as num?)?.toDouble() ??
            (e['center'] != null
                ? (e['center']['lon'] as num?)?.toDouble()
                : null) ??
            0;
        final pos = ll.LatLng(lat, lng);
        final dist = _haversine(center, pos);
        return PoliceStation(
          name: name,
          position: pos,
          distanceMeters: dist,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────

  Future<void> stopAll() async {
    stopCallStateListener();
    await stopSiren();
    await stopVibration();
    _sirenWasPlayingBeforeCall = false;
    _vibrationWasActiveBeforeCall = false;
  }

  // ── Helpers ────────────────────────────────────────────────────

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
}

class PoliceStation {
  final String name;
  final ll.LatLng position;
  final double distanceMeters;

  const PoliceStation({
    required this.name,
    required this.position,
    required this.distanceMeters,
  });

  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}
