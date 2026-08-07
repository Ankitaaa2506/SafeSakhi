import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  StreamSubscription<Position>? _positionSub;
  StreamController<Position>? _positionController;
  Position? _lastPosition;
  bool? _hasPermission;
  bool _initialized = false;

  Position? get lastPosition => _lastPosition;
  bool get hasLocation => _lastPosition != null;

  Stream<Position> get positionStream {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  Stream<Position> get onPositionChanged {
    _positionController ??= StreamController<Position>.broadcast();
    return _positionController!.stream;
  }

  Future<bool> handleLocationPermission() async {
    if (_hasPermission != null) return _hasPermission!;

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _hasPermission = false;
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _hasPermission = false;
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _hasPermission = false;
      return false;
    }
    _hasPermission = true;
    return true;
  }

  Future<Position?> getCurrentLocation() async {
    if (_lastPosition != null && _initialized) return _lastPosition;

    final hasPermission = await handleLocationPermission();
    if (!hasPermission) return null;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    _lastPosition = position;
    _initialized = true;
    _positionController?.add(position);
    return position;
  }

  void startBackgroundStream() {
    handleLocationPermission().then((hasPermission) {
      if (!hasPermission) return;
      _positionSub?.cancel();
      _positionSub = positionStream.listen((position) {
        _lastPosition = position;
        _positionController?.add(position);
      });
    });
  }

  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;
    _positionController?.close();
    _positionController = null;
  }
}
