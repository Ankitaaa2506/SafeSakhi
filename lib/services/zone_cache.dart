import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Safety classification for a road zone.
enum ZoneLevel { safe, moderate, danger }

/// A road zone fetched from Firestore.
class SafetyZone {
  final String id;
  final String? roadName;
  final double lat;
  final double lng;
  final double aiScore;
  final double radius;
  final ZoneLevel level;

  const SafetyZone({
    required this.id,
    this.roadName,
    required this.lat,
    required this.lng,
    required this.aiScore,
    required this.radius,
    required this.level,
  });

  factory SafetyZone.fromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final score = (data['aiScore'] as num?)?.toDouble() ?? 100.0;
    return SafetyZone(
      id: doc.id,
      roadName: data['roadName'] as String?,
      lat: (data['centerLatitude'] as num?)?.toDouble() ?? 0,
      lng: (data['centerLongitude'] as num?)?.toDouble() ?? 0,
      aiScore: score,
      radius: (data['radiusMeters'] as num?)?.toDouble() ?? 50,
      level: _classify(score),
    );
  }

  static ZoneLevel _classify(double score) {
    if (score >= 75) return ZoneLevel.safe;
    if (score >= 40) return ZoneLevel.moderate;
    return ZoneLevel.danger;
  }
}

/// Singleton in-memory cache for road safety zones.
///
/// Call [warmUp] once at app start. After that, [zones] returns instantly.
class ZoneCache {
  ZoneCache._();
  static final ZoneCache instance = ZoneCache._();

  List<SafetyZone> _zones = [];
  bool _loaded = false;

  /// Returns cached zones. Empty list if Firestore has no zones or fetch failed.
  List<SafetyZone> get zones => _zones;
  bool get isLoaded => _loaded;

  /// Fetch zones from Firestore once. Safe to call multiple times.
  Future<void> warmUp() async {
    if (_loaded) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('road_zones')
          .get(const GetOptions(source: Source.serverAndCache));
      _zones = snap.docs.map((d) => SafetyZone.fromDoc(d)).toList();
    } catch (_) {
      _zones = [];
    }
    _loaded = true;
  }

  /// Returns danger + moderate zones within [radiusMeters] of [lat],[lng].
  List<SafetyZone> dangerNear(double lat, double lng, double radiusMeters) {
    return _zones.where((z) {
      if (z.level == ZoneLevel.safe) return false;
      return _dist(lat, lng, z.lat, z.lng) <= radiusMeters;
    }).toList();
  }

  static double _dist(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
