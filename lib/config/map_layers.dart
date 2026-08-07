import 'dart:math';
import 'dart:developer' as developer;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Centralized MapTiler Streets v2 layer configuration.
///
/// Layer IDs are verified against the live style:
/// https://api.maptiler.com/maps/streets-v2/style.json
///
/// When MapTiler updates their style, only this file needs to change.
class MapLayerConfig {
  MapLayerConfig._();

  // ── Place / settlement symbol layers ──────────────────────────────
  static const List<String> placeLabelLayers = [
    'Country labels',
    'Capital city labels',
    'City labels',
    'State labels',
    'Town labels',
    'Place labels',
  ];

  // ── POI symbol layers ─────────────────────────────────────────────
  static const List<String> poiLabelLayers = [
    'Healthcare',
    'Education',
    'Station',
    'Airport',
    'Tourism',
    'Park',
    'Shopping',
    'Food',
    'Sport',
    'Public',
    'Culture',
    'Transport',
  ];

  // ── Road symbol layers (text labels on roads) ─────────────────────
  static const List<String> roadLabelLayers = [
    'Road labels',
    'Highway shield',
    'Highway shield (US)',
    'Highway shield interstate (US)',
    'Highway junction',
  ];

  // ── Road geometry layers (line features for hit-testing) ──────────
  static const List<String> roadGeometryLayers = [
    'Highway',
    'Major road',
    'Minor road',
    'Path',
  ];

  // ── Combined query groups ─────────────────────────────────────────

  /// All symbol layers that should respond to taps for place reviews.
  static List<String> get allPlaceLayers => [
        ...placeLabelLayers,
        ...poiLabelLayers,
      ];

  /// All layers that should respond to taps for road safety.
  static List<String> get allRoadLayers => [
        ...roadLabelLayers,
        ...roadGeometryLayers,
      ];

  /// Every layer we query during tap detection.
  static List<String> get allTappableLayers => [
        ...allPlaceLayers,
        ...allRoadLayers,
      ];

  /// Layers that need textAllowOverlap + textIgnorePlacement overrides
  /// so labels are always visible and tappable.
  static List<String> get layersNeedingOverlapOverride => [
        ...placeLabelLayers,
        ...poiLabelLayers,
        ...roadLabelLayers,
      ];

  // ── Debug utilities ───────────────────────────────────────────────

  static const bool debugEnabled = true;

  static void logTapDebug(String message) {
    if (debugEnabled) {
      developer.log(message, name: 'MapTap');
    }
  }

  /// Query all rendered features at [point] with NO layer filter,
  /// then log every feature's details for debugging.
  static Future<void> logAllFeaturesAtPoint(
    MapLibreMapController controller,
    Point<double> point,
  ) async {
    if (!debugEnabled) return;

    try {
      final allFeatures = await controller.queryRenderedFeatures(
        point,
        [], // empty = no layer filter = return everything
        null,
      );

      logTapDebug('═══ ALL features at (${point.x.toStringAsFixed(1)}, ${point.y.toStringAsFixed(1)}) ═══');
      logTapDebug('Total: ${allFeatures.length}');

      for (var i = 0; i < allFeatures.length; i++) {
        final f = allFeatures[i];
        final layer = f['layer'] as Map<String, dynamic>?;
        final layerId = layer?['id'] ?? 'unknown';
        final sourceLayer = layer?['source-layer'] ?? 'N/A';
        final geometryType = f['geometry']?['type'] ?? 'unknown';
        final props = f['properties'] as Map<String, dynamic>?;
        final name = props?['name'] ?? props?['ref'] ?? '';

        logTapDebug(
          '  [$i] layer=$layerId | source-layer=$sourceLayer | '
          'geometry=$geometryType | name=$name',
        );
      }

      logTapDebug('═══════════════════════════════════════════');
    } catch (e) {
      logTapDebug('ERROR querying all features: $e');
    }
  }

  /// Warn if a configured layer doesn't exist in the current style.
  static Future<void> validateLayers(MapLibreMapController controller) async {
    if (!debugEnabled) return;

    try {
      final allFeatures = await controller.queryRenderedFeatures(
        Point(0, 0), // arbitrary point — we just want to see if layers exist
        allTappableLayers,
        null,
      );
      // If we get here without error, the layers exist
      logTapDebug('Layer validation: all configured layers exist (${allFeatures.length} features at origin)');
    } catch (e) {
      logTapDebug('Layer validation WARNING: $e');
    }
  }
}
