import 'package:flutter/widgets.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/rust/api/galileo_api.dart' as rlib;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:math' as math;

class LayerController extends ChangeNotifier {
  final Map<String, int> _layerNames = {};
  final Map<String, FeatureEditController> _editors = {};
  final List<LayerConfig> layers;
  final int sessionId;
  MapViewport? _viewportBounds;
  MapViewport? get viewportBounds => _viewportBounds;

  double _zoomScale = 1.0;
  double get zoomScale => _zoomScale;

  double? _initialResolution;

  final List<OverlayWidget> _overlays = [];
  List<OverlayWidget> get overlays => List.unmodifiable(_overlays);

  void addOverlay(OverlayWidget overlay) {
    _overlays.add(overlay);
    notifyListeners();
  }

  void removeOverlay(OverlayWidget overlay) {
    if (_overlays.remove(overlay)) {
      notifyListeners();
    }
  }

  void clearOverlays() {
    _overlays.clear();
    notifyListeners();
  }

  T? editorFor<T extends FeatureEditController>(String layerName) {
    final e = _editors[layerName];
    return e is T ? e : null;
  }

  LayerController({required this.sessionId, required this.layers});

  /// Update Viewport
  Future<void> updateViewport(
    MapViewport? nativeViewport,
    MapSize mapSize,
  ) async {
    if (nativeViewport == null) return;
    _viewportBounds = MapViewport(
      xMin: nativeViewport.xMin,
      xMax: nativeViewport.xMax,
      yMin: nativeViewport.yMin,
      yMax: nativeViewport.yMax,
    );

    final coordWidth = nativeViewport.xMax - nativeViewport.xMin;
    if (coordWidth > 0 && mapSize.width > 0) {
      final resolution = coordWidth / mapSize.width;
      _initialResolution ??= resolution;
      _zoomScale = _initialResolution! / resolution;
    }

    for (final editor in _editors.values) {
      editor.updateViewport(_viewportBounds!);
    }

    notifyListeners();
  }

  /// Add a layer to the map
  Future<void> addLayer(LayerConfig layer) async {
    try {
      await layer.maybeWhen(
        widgetLayer: () async {},
        orElse: () async {
          await rlib.addSessionLayer(sessionId: sessionId, layerConfig: layer);
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error adding layer: $e');
      }
    }
  }

  /// creates a managed point layer on the rust side and stores the handle under name.
  Future<int?> addPointFeatureLayer(
    String name, {
    List<Point> initialPoints = const [],
  }) async {
    try {
      final id = await rlib.addPointFeatureLayer(
        sessionId: sessionId,
        initialPoints: initialPoints,
      );
      _layerNames[name] = id;
      return id;
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating point layer "$name": $e');
      return null;
    }
  }

  /// Creates a managed polygon layer on the rust side and stores the handle under name.
  Future<int?> addPolygonFeatureLayer(
    String name, {
    List<Polygon> initialPolygons = const [],
    PolygonEditController? editor,
  }) async {
    try {
      final id = await rlib.addPolygonFeatureLayer(
        sessionId: sessionId,
        initialPolygons: initialPolygons,
      );
      _layerNames[name] = id;

      if (editor != null) {
        _editors[name] = editor;
      }

      return id;
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating polygon layer "$name": $e');
      return null;
    }
  }

  Future<int> addPointToLayer(String layerName, Point point) async {
    final id = _layerNames[layerName];
    if (id == null) {
      if (kDebugMode) debugPrint('No point layer named "$layerName"');
      return -1;
    }
    try {
      return await rlib.addPointToLayer(
        sessionId: sessionId,
        layerId: id,
        point: point,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error adding point to "$layerName": $e');
      return -1;
    }
  }

  Future<bool> removePointFromLayer(String layerName, int index) async {
    final id = _layerNames[layerName];
    if (id == null) return false;
    try {
      return await rlib.removePointFromLayer(
        sessionId: sessionId,
        layerId: id,
        index: index,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error removing point from "$layerName": $e');
      return false;
    }
  }

  Future<int> addPolygonToLayer(String layerName, Polygon polygon) async {
    final id = _layerNames[layerName];
    if (id == null) {
      if (kDebugMode) debugPrint('No point layer named "$layerName"');
      return -1;
    }
    try {
      return await rlib.addPolygonToLayer(
        sessionId: sessionId,
        layerId: id,
        polygon: polygon,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error adding point to "$layerName": $e');
      return -1;
    }
  }

  Future<bool> removePolygonFromLayer(String layerName, int index) async {
    final id = _layerNames[layerName];
    if (id == null) return false;
    try {
      return await rlib.removePolygonFromLayer(
        sessionId: sessionId,
        layerId: id,
        index: index,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error removing point from "$layerName": $e');
      return false;
    }
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _editors.clear();
    super.dispose();
  }
}
