import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Converts a vertex [GeoLocation] to a screen [Offset] in one step.
Offset _geoToOffset(GeoLocation geo, Size size, MapViewport vp) {
  final s = geo.toScreen(height: size.height, width: size.width, vp: vp);
  return Offset(s.x, s.y);
}

class EditOverlayPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;

  const EditOverlayPainter({required this.vertices, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final pts = vertices.map((v) => _geoToOffset(v, size, viewport)).toList();

    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = const ui.Color(0x55FFEB3B)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const ui.Color(0xFFFFEB3B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(EditOverlayPainter old) =>
      old.vertices != vertices || old.viewport != viewport;
}

/// Draws the live preview of a polygon being drawn vertex-by-vertex.
/// Vertices are shown as blue dots; edges as dashed lines; if 3+ vertices
/// exist a translucent fill closes the shape.
class PendingPolygonPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;

  const PendingPolygonPainter({required this.vertices, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final pts = vertices.map((v) => _geoToOffset(v, size, viewport)).toList();

    // Translucent fill + dashed border when closed (3+ pts).
    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = const ui.Color(0x4400BFFF)
          ..style = PaintingStyle.fill,
      );
    }

    // Edge lines (open polyline).
    if (pts.length >= 2) {
      final edgePaint =
          Paint()
            ..color = const ui.Color(0xFF0288D1)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
      for (int i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(pts[i], pts[i + 1], edgePaint);
      }
      // Closing dashed preview line back to first vertex.
      final dashPaint =
          Paint()
            ..color = const ui.Color(0x880288D1)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
      canvas.drawLine(pts.last, pts.first, dashPaint);
    }
  }

  @override
  bool shouldRepaint(PendingPolygonPainter old) =>
      old.vertices != vertices || old.viewport != viewport;
}

class CountChip extends StatelessWidget {
  const CountChip({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final ui.Color color;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text(
        '$count $label',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class FeatureLayerManager {
  static const _pointLayerName = 'managed-points';
  static const _polygonLayerName = 'managed-polygons';

  final LayerController layerController;
  final PolygonEditController? _polygonEditController;

  final List<int> _pointIds = [];

  final Map<int, Polygon> _polygons = {};

  FeatureLayerManager({
    required this.layerController,
    PolygonEditController? polygonEditController,
  }) : _polygonEditController = polygonEditController;

  int get pointCount => _pointIds.length;
  int get polygonCount => _polygons.length;

  Map<int, Polygon> get polygons => Map.unmodifiable(_polygons);

  Future<void> initialize() async {
    await layerController.addPointFeatureLayer(_pointLayerName);
    await layerController.addPolygonFeatureLayer(
      _polygonLayerName,
      editor: _polygonEditController,
    );

    _polygonEditController?.attach(this);
  }

  void dispose() {
    _polygonEditController?.detach();
    _pointIds.clear();
    _polygons.clear();
  }

  // Handling primitive objects like Polygon and Points
  Future<void> addPoint(Point point) async {
    final id = await layerController.addPointToLayer(_pointLayerName, point);
    if (id >= 0) {
      _pointIds.add(id);
    } else {
      if (kDebugMode) debugPrint('addPoint: rust returned invalid id $id');
    }
  }

  Future<void> removeLastPoint() async {
    if (_pointIds.isEmpty) return;
    final id = _pointIds.last;
    final removed = await layerController.removePointFromLayer(
      _pointLayerName,
      id,
    );
    if (removed) {
      _pointIds.removeLast();
    } else {
      if (kDebugMode) {
        debugPrint('removeLastPoint: rust could not remove id $id');
      }
    }
  }

  Future<void> clearPoints() async {
    for (final id in List<int>.from(_pointIds)) {
      await layerController.removePointFromLayer(_pointLayerName, id);
    }
    _pointIds.clear();
  }

  Future<void> addPolygon(Polygon polygon) async {
    final id = await layerController.addPolygonToLayer(
      _polygonLayerName,
      polygon,
    );
    if (id >= 0) {
      _polygons[id] = polygon;
    } else {
      if (kDebugMode) {
        debugPrint('addPolygon: rust returned invalid id $id');
      }
    }
  }

  Future<int> updatePolygon(int oldId, Polygon updated) async {
    final removed = await layerController.removePolygonFromLayer(
      _polygonLayerName,
      oldId,
    );
    if (!removed) {
      if (kDebugMode) {
        debugPrint('updatePolygon: could not remove old id $oldId');
      }
    }
    _polygons.remove(oldId);

    final newId = await layerController.addPolygonToLayer(
      _polygonLayerName,
      updated,
    );
    if (newId >= 0) {
      _polygons[newId] = updated;
    } else {
      if (kDebugMode) {
        debugPrint('updatePolygon: rust returned invalid id $newId');
      }
    }
    return newId;
  }

  Future<void> removeLastPolygon() async {
    if (_polygons.isEmpty) return;
    final id = _polygons.keys.last;
    final removed = await layerController.removePolygonFromLayer(
      _polygonLayerName,
      id,
    );
    if (removed) {
      _polygons.remove(id);
    } else {
      if (kDebugMode) {
        debugPrint('removeLastPolygon: rust could not remove id $id');
      }
    }
  }

  Future<void> clearPolygons() async {
    for (final id in List<int>.from(_polygons.keys)) {
      await layerController.removePolygonFromLayer(_polygonLayerName, id);
    }
    _polygons.clear();
  }
}

abstract class FeatureEditController extends ChangeNotifier {
  bool get isActive;
  void updateViewport(MapViewport viewport);
  void handlePointerDown(PointerDownEvent event, Size mapSize);
  void handlePointerMove(PointerMoveEvent event, Size mapSize);
  Future<void> handlePointerUp(PointerUpEvent event, Size mapSize);
  bool hitTestHandles(Offset localPosition, Size mapSize) => false;
}

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

  PolygonEditController({this.onStatusMessage, this.onSelectionChanged});

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
  /// and not currently drawing.
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
        fillColor: Color(r: 0.2, g: 0.5, b: 0.9, a: 0.8),
        strokeColor: Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
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
      final scr = _geoToOffset(_editingVertices[i], size, vp);
      if ((scr - pos).distance < _vertexHitR) return i;
    }
    return null;
  }

  int? _hitEdgeMidpoint(Offset pos, Size size) {
    final vp = _viewport;
    if (vp == null) return null;
    for (int i = 0; i < _editingVertices.length; i++) {
      final a = _geoToOffset(_editingVertices[i], size, vp);
      final b = _geoToOffset(
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
      poly.points.map((t) => _geoToOffset(t, size, vp)).toList(),
    );
  }

  @override
  void dispose() {
    _features = null;
    super.dispose();
  }
}
