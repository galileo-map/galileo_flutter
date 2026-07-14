import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Controller that manages the pending-vertex state for drawing a new polygon.
///
/// Exposes a simple API: [addVertex], [undoLastVertex], [cancel], [finish].
/// Listeners are notified on every state change so overlays and toolbars
/// can rebuild.
class PolygonDrawController extends ChangeNotifier {
  MapViewport? _viewport;

  MapViewport? get viewport => _viewport;
  List<GeoLocation> _pendingVertices = [];

  Offset? _pointerDownPos;
  bool get isDrawing => _pendingVertices.isNotEmpty;

  static const _tapThreshold = 10.0;

  // callbacks
  final void Function(String message)? onStatusMessage;

  PolygonDrawController({this.onStatusMessage});

  FeatureLayerManager? _features;

  /// Layer controller
  LayerController? get layerController => _features?.layerController;

  /// Unmodifiable view of the vertices placed so far.
  List<GeoLocation> get pendingVertices => List.unmodifiable(_pendingVertices);

  /// Number of vertices placed so far.
  int get vertexCount => _pendingVertices.length;

  /// Whether the polygon has enough vertices (≥3) to be finished.
  bool get canFinish => _pendingVertices.length >= 3;

  void attach(FeatureLayerManager features) => _features = features;

  void detach() {
    _features = null;
  }

  /// Add a vertex at the given lat/lon.
  void addVertex(GeoLocation loc) {
    _pendingVertices.add(loc);
    notifyListeners();
    final n = _pendingVertices.length;
    onStatusMessage?.call(
      n < 3
          ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
          : '$n vertices — tap "Finish" to create polygon or keep adding',
    );
  }

  void updateViewport(MapViewport viewport) {
    _viewport = viewport;
    notifyListeners();
  }

  void handlePointerDown(PointerDownEvent event, Size mapSize) {
    _pointerDownPos = event.localPosition;
  }

  void handlePointerMove(PointerMoveEvent event, Size mapSize) {
    // No-op for now.
  }

  void handlePointerUp(PointerUpEvent event, Size mapSize) {
    final down = _pointerDownPos;
    _pointerDownPos = null;
    if (down == null) return;

    if ((event.localPosition - down).distance < _tapThreshold) {
      final vp = viewport;
      if (vp == null) return;

      final screenPos = ScreenLocation(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
      ).toGeographical(height: mapSize.height, width: mapSize.width, vp: vp);
      addVertex(screenPos);
    }
  }

  void handlePointerCancel(PointerCancelEvent event, Size mapSize) {
    _pointerDownPos = null;
  }

  /// Remove the most recently placed vertex.
  void undoLastVertex() {
    if (_pendingVertices.isEmpty) return;
    _pendingVertices.removeLast();
    final n = _pendingVertices.length;
    onStatusMessage?.call(
      n == 0
          ? 'Tap map to start drawing a polygon'
          : n < 3
          ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
          : '$n vertices — tap "Finish" to create polygon or keep adding',
    );
    notifyListeners();
  }

  /// Cancel the current draw session, discarding all pending vertices.
  void cancel() {
    _pendingVertices = [];
    onStatusMessage?.call('Tap map to add features');
    notifyListeners();
  }

  /// [style] defaults to a blue fill with white stroke if not provided.
  /// Returns silently if fewer than 3 vertices have been placed.
  Future<void> finish(PolygonStyle style) async {
    if (_pendingVertices.length < 3) return;

    final effectiveStyle = style;

    await _features?.addPolygon(
      Polygon(points: List.from(_pendingVertices), style: effectiveStyle),
    );

    _pendingVertices = [];
    onStatusMessage?.call(
      'Polygon created — total: ${_features?.polygonCount}  (tap polygon to edit)',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _pendingVertices = [];
    super.dispose();
  }
}
