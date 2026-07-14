import 'package:galileo_flutter/galileo_flutter.dart';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:galileo_flutter/src/utils.dart';

class PolygonEditController extends FeatureEditController {
  // config editor
  static const _tapThreshold = 10.0;
  static const _vertexHitR = 14.0;
  static const _midpointHitR = 12.0;

  // callbacks
  final void Function(String message)? onStatusMessage;

  final void Function(int? polygonId)? onSelectionChanged;

  FeatureLayerManager? _features;

  int? _selectedPolygonId;
  List<GeoLocation> _editingVertices = [];
  MapViewport? _viewport;
  int? _draggingVertexIndex;
  Offset? _pointerDownPos;
  bool _wasActiveOnPointerDown = false;

  PolygonEditController({this.onStatusMessage, this.onSelectionChanged});

  /// True while the user is actively dragging a vertex handle.
  bool get isDraggingVertex => _draggingVertexIndex != null;

  /// Index of the vertex currently being dragged, or null.
  int? get draggingVertexIndex => _draggingVertexIndex;

  /// True if the editor was active at the start of the current gesture pointer down.
  bool get wasActiveOnPointerDown => _wasActiveOnPointerDown;

  @override
  bool get shouldSuppressPan => isDraggingVertex;

  @override
  bool get isActive => _selectedPolygonId != null;

  int? get selectedPolygonId => _selectedPolygonId;
  List<GeoLocation> get editingVertices => List.unmodifiable(_editingVertices);
  MapViewport? get viewport => _viewport;

  LayerController? get layerController => _features?.layerController;

  void attach(FeatureLayerManager features) => _features = features;

  void detach() {
    _features = null;
    _deselect(notify: false);
  }

  @override
  void updateViewport(MapViewport viewport) {
    _viewport = viewport;
    notifyListeners();
  }

  bool pointInPolygon(Offset p, List<Offset> poly) {
    int crossings = 0;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      if ((a.dy <= p.dy && b.dy > p.dy) || (b.dy <= p.dy && a.dy > p.dy)) {
        if (p.dx < a.dx + (p.dy - a.dy) / (b.dy - a.dy) * (b.dx - a.dx)) {
          crossings++;
        }
      }
    }
    return crossings.isOdd;
  }

  /// the widget calls this in its main tap dispatcher when in polygon draw mode
  /// and currently editing.
  Future<bool> trySelectAt(
    Offset screenPos,
    Size mapSize,
    MapViewport vp,
  ) async {
    _viewport = vp;
    final features = _features;
    if (features == null) return false;

    for (final id in features.polygons.keys) {
      if (_hitPolygonBody(screenPos, id, mapSize)) {
        await _selectPolygon(id);
        return true;
      }
    }
    return false;
  }

  void deselect() => _deselect();

  /// Returns true if the given [localPosition] hits a vertex or midpoint handle.
  @override
  bool hitTestHandles(Offset localPosition, Size mapSize) {
    if (!isActive) return false;
    return _hitVertex(localPosition, mapSize) != null ||
        _hitEdgeMidpoint(localPosition, mapSize) != null;
  }

  Future<void> _selectPolygon(int id) async {
    final poly = _features?.polygons[id];
    if (poly == null) return;
    _selectedPolygonId = id;
    _editingVertices = List.from(poly.points);
    onSelectionChanged?.call(id);
    onStatusMessage?.call(
      'Editing polygon — drag vertex to move · tap vertex to delete · tap ＋ to insert',
    );
    notifyListeners();
  }

  void _deselect({bool notify = true}) {
    final hadSelection = _selectedPolygonId != null;
    _selectedPolygonId = null;
    _editingVertices = [];
    _draggingVertexIndex = null;
    _pointerDownPos = null;
    if (hadSelection) onSelectionChanged?.call(null);
    onStatusMessage?.call('Tap map to add features');
    if (notify) notifyListeners();
  }

  @override
  void handlePointerDown(PointerDownEvent event, Size mapSize) {
    _wasActiveOnPointerDown = isActive;
    if (!isActive) return;
    _pointerDownPos = event.localPosition;
    _draggingVertexIndex = _hitVertex(event.localPosition, mapSize);
  }

  @override
  void handlePointerMove(PointerMoveEvent event, Size mapSize) {
    final vi = _draggingVertexIndex;
    final vp = _viewport;
    if (vi == null || vp == null || !isActive) return;
    final pos = event.localPosition;
    _editingVertices[vi] = ScreenLocation(
      x: pos.dx,
      y: pos.dy,
    ).toGeographical(vp: vp, height: mapSize.height, width: mapSize.width);
    notifyListeners(); // live vertex drag
  }

  @override
  Future<void> handlePointerUp(PointerUpEvent event, Size mapSize) async {
    if (!isActive) return;

    final down = _pointerDownPos;
    final vi = _draggingVertexIndex;
    final isTap =
        down == null || (event.localPosition - down).distance < _tapThreshold;

    _draggingVertexIndex = null;
    _pointerDownPos = null;

    if (vi != null) {
      isTap ? await _removeVertex(vi) : await _commitEdits();
    } else if (isTap) {
      final ei = _hitEdgeMidpoint(event.localPosition, mapSize);
      if (ei != null) {
        await _insertVertexAfterEdge(ei);
      } else {
        _deselect();
      }
    }
  }

  Future<void> _commitEdits() async {
    final features = _features;
    final id = _selectedPolygonId;
    if (features == null || id == null || _editingVertices.length < 3) return;

    final updated = Polygon(
      points: List.from(_editingVertices),
      style: PolygonStyle(
        fillColor: Color(0x338FE6CC).toGalileo(),
        strokeColor: Color(0xFFFFFFFF).toGalileo(),
        strokeWidth: 2.0,
        strokeOffset: 0.0,
      ),
    );

    final newId = await features.updatePolygon(id, updated);
    _selectedPolygonId = newId;
    onStatusMessage?.call(
      'Polygon updated — ${_editingVertices.length} vertices',
    );
    notifyListeners();
  }

  Future<void> _removeVertex(int index) async {
    if (_editingVertices.length <= 3) {
      onStatusMessage?.call('Minimum 3 vertices');
      return;
    }
    _editingVertices.removeAt(index);
    notifyListeners();
    await _commitEdits();
  }

  Future<void> _insertVertexAfterEdge(int edgeIndex) async {
    /// TODO
    final a = _editingVertices[edgeIndex];
    final b = _editingVertices[(edgeIndex + 1) % _editingVertices.length];

    double midLng = (a.longitude + b.longitude) / 2;

    if ((a.longitude - b.longitude).abs() > 180) {
      midLng = (midLng + 180) % 360;
      if (midLng > 180) midLng -= 360;
    }
    final mid = GeoLocation(
      latitude: (a.latitude + b.latitude) / 2,
      longitude: midLng,
    );

    _editingVertices.insert(edgeIndex + 1, mid);
    notifyListeners();
    await _commitEdits();
  }

  int? _hitVertex(Offset pos, Size size) {
    final vp = _viewport;
    if (vp == null) return null;
    for (int i = 0; i < _editingVertices.length; i++) {
      final scr = geoToOffset(_editingVertices[i], size, vp);
      if ((scr - pos).distance < _vertexHitR) return i;
    }
    return null;
  }

  int? _hitEdgeMidpoint(Offset pos, Size size) {
    final vp = _viewport;
    if (vp == null) return null;
    for (int i = 0; i < _editingVertices.length; i++) {
      final a = geoToOffset(_editingVertices[i], size, vp);
      final b = geoToOffset(
        _editingVertices[(i + 1) % _editingVertices.length],
        size,
        vp,
      );
      final mid = (a + b) / 2;
      if ((mid - pos).distance < _midpointHitR) return i;
    }
    return null;
  }

  bool _hitPolygonBody(Offset pos, int id, Size size) {
    final poly = _features?.polygons[id];
    final vp = _viewport;
    if (poly == null || vp == null) return false;
    return pointInPolygon(
      pos,
      poly.points.map((t) => geoToOffset(t, size, vp)).toList(),
    );
  }

  @override
  void dispose() {
    _features = null;
    super.dispose();
  }
}
