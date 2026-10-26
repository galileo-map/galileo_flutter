import 'package:flutter/widgets.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/rust/api/galileo_api.dart' as rlib;
import 'package:logging/logging.dart';

final _log = Logger('LayerController');

class LayerController extends ChangeNotifier {
  final Map<String, int> _layerNames = {};
  final Map<String, FeatureEditController> _editors = {};
  final List<LayerConfig> layers;
  final int sessionId;
  MapViewport? _viewportBounds;
  MapViewport? get viewportBounds => _viewportBounds;

  final ValueNotifier<MapViewport?> _viewportNotifier =
      ValueNotifier<MapViewport?>(null);

  /// Fires only when the viewport actually changes. Use this as a repaint
  /// trigger (e.g. `FlowDelegate(repaint: ...)`) so widgets are repositioned
  /// without being rebuilt on every rendered frame.
  Listenable get viewportListenable => _viewportNotifier;

  double _zoomScale = 1.0;
  double get zoomScale => _zoomScale;

  double? _initialResolution;

  final List<OverlayWidget> _overlays = [];
  List<OverlayWidget> _overlaysView = const [];

  /// Stable identity across reads; only recreated when overlays are
  /// added/removed/cleared, so `shouldRepaint` can compare by identity.
  List<OverlayWidget> get overlays => _overlaysView;

  final ValueNotifier<int> _overlaysRevision = ValueNotifier<int>(0);

  /// Fires only when the overlay list membership changes. Use this to rebuild
  /// the overlay layer instead of listening to every viewport notification.
  Listenable get overlaysRevision => _overlaysRevision;

  void _overlaysChanged() {
    _overlaysView = List.unmodifiable(_overlays);
    _overlaysRevision.value++;
  }

  void addOverlay(OverlayWidget overlay) {
    _overlays.add(overlay);
    _overlaysChanged();
    notifyListeners();
  }

  void removeOverlay(OverlayWidget overlay) {
    if (_overlays.remove(overlay)) {
      _overlaysChanged();
      notifyListeners();
    }
  }

  void clearOverlays() {
    if (_overlays.isNotEmpty) {
      _overlays.clear();
      _overlaysChanged();
      notifyListeners();
    }
  }

  T? editorFor<T extends FeatureEditController>(String layerName) {
    final e = _editors[layerName];
    return e is T ? e : null;
  }

  bool _drawSuppressPan = false;
  bool get drawSuppressPan => _drawSuppressPan;
  set drawSuppressPan(bool value) {
    if (_drawSuppressPan != value) {
      _drawSuppressPan = value;
      notifyListeners();
    }
  }

  /// True when any registered editor is performing a drag gesture and the map
  /// should not process pointer-move events as pans.
  bool get shouldSuppressPan =>
      _drawSuppressPan || _editors.values.any((e) => e.shouldSuppressPan);

  LayerController({required this.sessionId, required this.layers});

  /// Applies the viewport that was used to render the current texture frame.
  void updateViewport(MapViewport? nativeViewport, MapSize mapSize) {
    if (nativeViewport == null) return;
    final viewport = nativeViewport;

    final coordWidth = viewport.xMax - viewport.xMin;
    double zoomScale = _zoomScale;
    if (coordWidth > 0 && mapSize.width > 0) {
      final resolution = coordWidth / mapSize.width;
      _initialResolution ??= resolution;
      zoomScale = _initialResolution! / resolution;
    }

    // Skip notifications entirely when nothing changed; rendered frames often
    // repeat the same viewport and would otherwise rebuild/repaint the whole
    // overlay layer for nothing.
    if (viewport == _viewportBounds && zoomScale == _zoomScale) {
      return;
    }

    _viewportBounds = viewport;
    _zoomScale = zoomScale;

    for (final editor in _editors.values) {
      editor.updateViewport(viewport);
    }

    _viewportNotifier.value = viewport;
    notifyListeners();
  }

  /// Add a layer to the map
  Future<void> addLayer(LayerConfig layer) async {
    try {
      switch (layer) {
        case LayerConfig.widgetLayer:
          break;
        default:
          await rlib.addSessionLayer(sessionId: sessionId, layerConfig: layer);
      }
    } catch (e) {
      _log.severe('Error adding layer', e);
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
      _log.severe('Error creating point layer "$name"', e);
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
      _log.severe('Error creating polygon layer "$name"', e);
      return null;
    }
  }

  Future<int> addPointToLayer(String layerName, Point point) async {
    final id = _layerNames[layerName];
    if (id == null) {
      _log.warning('No point layer named "$layerName"');
      return -1;
    }
    try {
      return await rlib.addPointToLayer(
        sessionId: sessionId,
        layerId: id,
        point: point,
      );
    } catch (e) {
      _log.severe('Error adding point to "$layerName"', e);
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
      _log.severe('Error removing point from "$layerName"', e);
      return false;
    }
  }

  Future<int> addPolygonToLayer(String layerName, Polygon polygon) async {
    final id = _layerNames[layerName];
    if (id == null) {
      _log.warning('No polygon layer named "$layerName"');
      return -1;
    }
    try {
      return await rlib.addPolygonToLayer(
        sessionId: sessionId,
        layerId: id,
        polygon: polygon,
      );
    } catch (e) {
      _log.severe('Error adding polygon to "$layerName"', e);
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
      _log.severe('Error removing polygon from "$layerName"', e);
      return false;
    }
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _editors.clear();
    _viewportNotifier.dispose();
    _overlaysRevision.dispose();
    super.dispose();
  }
}
