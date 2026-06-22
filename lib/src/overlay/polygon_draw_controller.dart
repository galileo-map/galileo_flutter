import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Controller that manages the pending-vertex state for drawing a new polygon.
///
/// Exposes a simple API: [addVertex], [undoLastVertex], [cancel], [finish].
/// Listeners are notified on every state change so overlays and toolbars
/// can rebuild.
class PolygonDrawController extends ChangeNotifier {
  final LayerController _layerController;
  final FeatureLayerManager _features;

  List<GeoLocation> _pendingVertices = [];

  /// Layer controller
  LayerController get layerController => _layerController;

  /// Unmodifiable view of the vertices placed so far.
  List<GeoLocation> get pendingVertices => List.unmodifiable(_pendingVertices);

  /// Whether a draw session is in progress (at least one vertex placed).
  bool get isDrawing => _pendingVertices.isNotEmpty;

  /// Number of vertices placed so far.
  int get vertexCount => _pendingVertices.length;

  /// Whether the polygon has enough vertices (≥3) to be finished.
  bool get canFinish => _pendingVertices.length >= 3;

  /// Human-readable status message describing the current state.
  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  PolygonDrawController(this._features, this._layerController);

  /// Add a vertex at the given lat/lon.
  void addVertex(GeoLocation loc) {
    _pendingVertices.add(loc);
    final n = _pendingVertices.length;
    _statusMessage =
        n < 3
            ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
            : '$n vertices — tap "Finish" to create polygon or keep adding';
    notifyListeners();
  }

  /// Remove the most recently placed vertex.
  void undoLastVertex() {
    if (_pendingVertices.isEmpty) return;
    _pendingVertices.removeLast();
    final n = _pendingVertices.length;
    _statusMessage =
        n == 0
            ? 'Tap map to start drawing a polygon'
            : n < 3
            ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
            : '$n vertices — tap "Finish" to create polygon or keep adding';
    notifyListeners();
  }

  /// Cancel the current draw session, discarding all pending vertices.
  void cancel() {
    _pendingVertices = [];
    _statusMessage = 'Tap map to add features';
    notifyListeners();
  }

  /// [style] defaults to a blue fill with white stroke if not provided.
  /// Returns silently if fewer than 3 vertices have been placed.
  Future<void> finish(PolygonStyle style) async {
    if (_pendingVertices.length < 3) return;

    final effectiveStyle = style;

    await _features.addPolygon(
      Polygon(points: List.from(_pendingVertices), style: effectiveStyle),
    );

    _pendingVertices = [];
    _statusMessage =
        'Polygon created — total: ${_features.polygonCount}  (tap polygon to edit)';
    notifyListeners();
  }

  @override
  void dispose() {
    _pendingVertices = [];
    super.dispose();
  }
}
