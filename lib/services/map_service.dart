import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const _keyLat = 'map_lat';
  static const _keyLng = 'map_lng';
  static const _keyZoom = 'map_zoom';
  static const _keyBearing = 'map_bearing';
  static const _keyHasSaved = 'map_has_saved';

  Future<void> saveCameraState(LatLng center, double zoom, double bearing) async {
    final prefs = await _getPrefs();
    await prefs.setDouble(_keyLat, center.latitude);
    await prefs.setDouble(_keyLng, center.longitude);
    await prefs.setDouble(_keyZoom, zoom);
    await prefs.setDouble(_keyBearing, bearing);
    await prefs.setBool(_keyHasSaved, true);
  }

  Future<({LatLng center, double zoom})?> restoreCameraState() async {
    final prefs = await _getPrefs();
    final hasSaved = prefs.getBool(_keyHasSaved) ?? false;
    if (!hasSaved) return null;
    final lat = prefs.getDouble(_keyLat) ?? 28.6139;
    final lng = prefs.getDouble(_keyLng) ?? 77.2090;
    final zoom = prefs.getDouble(_keyZoom) ?? 14.0;
    return (center: LatLng(lat, lng), zoom: zoom);
  }

  static double distanceInMeters(LatLng a, LatLng b) {
    return const Distance().distance(a, b);
  }
}
