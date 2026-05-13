//ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/galileo_map_controller.dart';
import 'package:galileo_flutter/src/galileo_feature_editor.dart';
import 'package:galileo_flutter/src/galileo_layer_controller.dart';
import 'dart:ui' as ui;

const MAP_TILER_API_KEY = '';
const MAP_TILER_URL_TEMPLATE =
    'https://api.maptiler.com/tiles/v3-openmaptiles/{z}/{x}/{y}.pbf?key=$MAP_TILER_API_KEY';

const _kMapSize = MapSize(width: 800, height: 600);
const _kMapConfig = MapInitConfig(
  backgroundColor: (0.1, 0.1, 0, 0.5),
  enableMultisampling: true,
  latlon: (0.0, 0.0),
  mapSize: _kMapSize,
  zoomLevel: 10,
);

enum DrawMode { point, polygon }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception is AssertionError &&
        details.exception.toString().contains('KeyDownEvent is dispatched')) {
      return;
    }
    FlutterError.dumpErrorToConsole(details);
  };
  await initGalileo();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galileo Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const GalileoMapPage(),
    );
  }
}

class GalileoMapPage extends StatefulWidget {
  const GalileoMapPage({super.key});
  @override
  State<GalileoMapPage> createState() => _GalileoMapPageState();
}

class _GalileoMapPageState extends State<GalileoMapPage> {
  String statusMessage = 'Loading...';
  String _layerConfigString = 'osm_tile_layer';

  GalileoMapController? _controller;
  late Future<(GalileoMapController?, String?)> _controllerFuture;

  static const _pointLayerName = 'points';
  static const _polygonLayerName = 'polygons';
  bool _layerReady = false;

  final Map<int, Point> _managedPoints = {};
  final Map<int, Polygon> _managedPolygons = {};

  DrawMode _drawMode = DrawMode.point;

  Offset? _pointerDownPosition;
  static const _tapThreshold = 10.0;

  // Edit-mode state
  int? _selectedPolygonId;
  List<(double, double)> _editingVertices = [];
  ViewportBounds? _cachedViewport;

  int? _draggingVertexIndex;
  Offset? _editPointerDownPos;

  static const _vertexHitR = 14.0;
  static const _midpointHitR = 12.0;

  bool get _isEditing => _selectedPolygonId != null;

  // Pending-polygon draw state
  List<(double, double)> _pendingVertices = [];
  bool get _isDrawingPolygon => _pendingVertices.isNotEmpty;

  // Layout key
  final _mapStackKey = GlobalKey();

  Size get _currentMapSize {
    final rb = _mapStackKey.currentContext?.findRenderObject() as RenderBox?;
    return rb?.size ?? const Size(800, 600);
  }

  @override
  void initState() {
    super.initState();
    _controllerFuture = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [LayerConfig.osm()],
    );
  }

  //  Viewport helpers

  Future<void> _refreshViewport() async {
    final vp = await _controller?.getViewport();
    if (vp == null || !mounted) return;
    setState(
      () =>
          _cachedViewport = ViewportBounds(
            xMin: vp.xMin,
            xMax: vp.xMax,
            yMin: vp.yMin,
            yMax: vp.yMax,
          ),
    );
  }

  // Layer management

  Future<void> _switchLayer(LayerConfig newLayer) async {
    setState(() {
      _layerReady = false;
      statusMessage = 'Loading...';
    });
    _controller?.dispose();
    _controller = null;
    _managedPoints.clear();
    _managedPolygons.clear();
    _selectedPolygonId = null;
    _editingVertices = [];
    _pendingVertices = [];

    final f = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [newLayer],
    );
    setState(() => _controllerFuture = f);

    final (ctrl, err) = await f;
    if (!mounted) return;
    if (err != null || ctrl == null) {
      setState(() => statusMessage = 'Error: ${err ?? "unknown"}');
      return;
    }
    await _initManagedLayer(ctrl);
  }

  Future<void> _initManagedLayer(GalileoMapController ctrl) async {
    setState(() => _controller = ctrl);
    await ctrl.layer_controller.addPointFeatureLayer(_pointLayerName);
    await ctrl.layer_controller.addPolygonFeatureLayer(_polygonLayerName);
    setState(() {
      _layerReady = true;
      statusMessage = 'Tap map to add features';
    });
  }

  // Edit-mode helpers

  Future<void> _selectPolygon(int id) async {
    final poly = _managedPolygons[id];
    if (poly == null) return;
    await _refreshViewport();
    if (!mounted) return;
    setState(() {
      _selectedPolygonId = id;
      _editingVertices = List.from(poly.points);
      statusMessage =
          'Editing polygon — drag vertex to move · tap vertex to delete · tap ＋ to insert';
    });
  }

  void _deselectPolygon() {
    setState(() {
      _selectedPolygonId = null;
      _editingVertices = [];
      _draggingVertexIndex = null;
      _editPointerDownPos = null;
      statusMessage = 'Tap map to add features';
    });
  }

  int? _hitVertex(Offset pos, Size size) {
    final vp = _cachedViewport;
    if (vp == null) return null;
    for (int i = 0; i < _editingVertices.length; i++) {
      if ((MapProjection.latLonToScreen(_editingVertices[i], size, vp) - pos)
              .distance <
          _vertexHitR)
        return i;
    }
    return null;
  }

  int? _hitEdgeMidpoint(Offset pos, Size size) {
    final vp = _cachedViewport;
    if (vp == null) return null;
    for (int i = 0; i < _editingVertices.length; i++) {
      final a = MapProjection.latLonToScreen(_editingVertices[i], size, vp);
      final b = MapProjection.latLonToScreen(
        _editingVertices[(i + 1) % _editingVertices.length],
        size,
        vp,
      );
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      if ((mid - pos).distance < _midpointHitR) return i;
    }
    return null;
  }

  bool _hitPolygonBody(Offset pos, int id, Size size) {
    final poly = _managedPolygons[id];
    final vp = _cachedViewport;
    if (poly == null || vp == null) return false;
    final screenPts =
        poly.points
            .map((t) => MapProjection.latLonToScreen(t, size, vp))
            .toList();
    return MapProjection.pointInPolygon(pos, screenPts);
  }

  Future<void> _commitEditedPolygon() async {
    final ctrl = _controller;
    final id = _selectedPolygonId;
    if (ctrl == null || id == null || _editingVertices.length < 3) return;

    await ctrl.layer_controller.removePolygonFromLayer(_polygonLayerName, id);
    _managedPolygons.remove(id);

    final poly = Polygon(
      points: List.from(_editingVertices),
      style: PolygonStyle(
        fillColor: Color(r: 0.2, g: 0.5, b: 0.9, a: 0.8),
        strokeColor: Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        strokeWidth: 2.0,
        strokeOffset: 0.0,
      ),
    );
    final newId = await ctrl.layer_controller.addPolygonToLayer(
      _polygonLayerName,
      poly,
    );
    if (!mounted) return;
    setState(() {
      _managedPolygons[newId] = poly;
      _selectedPolygonId = newId;
      statusMessage = 'Polygon updated — ${_editingVertices.length} vertices';
    });
  }

  Future<void> _removeVertex(int index) async {
    if (_editingVertices.length <= 3) {
      setState(() => statusMessage = 'Minimum 3 vertices');
      return;
    }
    setState(() => _editingVertices.removeAt(index));
    await _commitEditedPolygon();
  }

  Future<void> _insertVertexAfterEdge(int edgeIndex) async {
    final a = _editingVertices[edgeIndex];
    final b = _editingVertices[(edgeIndex + 1) % _editingVertices.length];
    final mid = ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2);
    setState(() => _editingVertices.insert(edgeIndex + 1, mid));
    await _commitEditedPolygon();
  }

  void _handleEditPointerDown(PointerDownEvent e) {
    _editPointerDownPos = e.localPosition;
    _draggingVertexIndex = _hitVertex(e.localPosition, _currentMapSize);
  }

  void _handleEditPointerMove(PointerMoveEvent e) {
    final vi = _draggingVertexIndex;
    final vp = _cachedViewport;
    if (vi == null || vp == null) return;
    final coord = MapProjection.screenToLatLon(
      e.localPosition,
      _currentMapSize,
      vp,
    );
    setState(() => _editingVertices[vi] = coord);
  }

  Future<void> _handleEditPointerUp(PointerUpEvent e) async {
    final size = _currentMapSize;
    final down = _editPointerDownPos;
    final vi = _draggingVertexIndex;
    final isTap =
        down == null || (e.localPosition - down).distance < _tapThreshold;

    _draggingVertexIndex = null;
    _editPointerDownPos = null;

    if (vi != null) {
      if (isTap) {
        await _removeVertex(vi);
      } else {
        await _commitEditedPolygon();
      }
    } else if (isTap) {
      final ei = _hitEdgeMidpoint(e.localPosition, size);
      if (ei != null) {
        await _insertVertexAfterEdge(ei);
      } else {
        _deselectPolygon();
      }
    }
  }

  // Pending-polygon helpers

  Future<void> _addPendingVertex(double lat, double lon) async {
    if (_cachedViewport == null) await _refreshViewport();
    if (!mounted) return;
    setState(() {
      _pendingVertices.add((lat, lon));
      final n = _pendingVertices.length;
      statusMessage =
          n < 3
              ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
              : '$n vertices — tap "Finish" to create polygon or keep adding';
    });
  }

  Future<void> _finishPendingPolygon() async {
    final ctrl = _controller;
    if (ctrl == null || _pendingVertices.length < 3) return;

    final polygon = Polygon(
      points: List.from(_pendingVertices),
      style: PolygonStyle(
        fillColor: Color(r: 0.2, g: 0.5, b: 0.9, a: 0.8),
        strokeColor: Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        strokeWidth: 2.0,
        strokeOffset: 0.0,
      ),
    );
    final id = await ctrl.layer_controller.addPolygonToLayer(
      _polygonLayerName,
      polygon,
    );
    if (!mounted) return;
    setState(() {
      _managedPolygons[id] = polygon;
      _pendingVertices = [];
      statusMessage =
          'Polygon created — total: ${_managedPolygons.length}  (tap polygon to edit)';
    });
  }

  void _cancelPendingPolygon() {
    setState(() {
      _pendingVertices = [];
      statusMessage = 'Tap map to add features';
    });
  }

  void _undoLastPendingVertex() {
    if (_pendingVertices.isEmpty) return;
    setState(() {
      _pendingVertices.removeLast();
      final n = _pendingVertices.length;
      statusMessage =
          n == 0
              ? 'Tap map to start drawing a polygon'
              : n < 3
              ? 'Vertex $n placed — tap ${3 - n} more to enable finishing'
              : '$n vertices — tap "Finish" to create polygon or keep adding';
    });
  }

  //  Main tap dispatcher

  Future<void> _addFeatureAtScreenPos(double x, double y, Size size) async {
    final ctrl = _controller;
    if (ctrl == null || !_layerReady) return;

    final viewport = await ctrl.getViewport();
    if (viewport == null) return;

    final vp = ViewportBounds(
      xMin: viewport.xMin,
      xMax: viewport.xMax,
      yMin: viewport.yMin,
      yMax: viewport.yMax,
    );
    if (mounted) setState(() => _cachedViewport = vp);

    final (lat, lon) = MapProjection.screenToLatLon(Offset(x, y), size, vp);

    if (_drawMode == DrawMode.point) {
      await _addPoint(ctrl, lat, lon);
    } else {
      if (_isDrawingPolygon) {
        await _addPendingVertex(lat, lon);
        return;
      }
      final tapPos = Offset(x, y);
      for (final entry in _managedPolygons.entries) {
        if (_hitPolygonBody(tapPos, entry.key, size)) {
          await _selectPolygon(entry.key);
          return;
        }
      }
      await _addPendingVertex(lat, lon);
    }
  }

  // Point helpers

  Future<void> _addPoint(
    GalileoMapController ctrl,
    double lat,
    double lon,
  ) async {
    final point = Point(
      coordinate: (lat, lon),
      style: PointStyle(
        fillColor: Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0),
        size: 8.0,
      ),
    );
    final id = await ctrl.layer_controller.addPointToLayer(
      _pointLayerName,
      point,
    );
    if (mounted) {
      setState(() {
        _managedPoints[id] = point;
        statusMessage =
            'Point at (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}) '
            '— total: ${_managedPoints.length}';
      });
    }
  }

  Future<void> _removeLastPoint() async {
    final ctrl = _controller;
    if (ctrl == null || _managedPoints.isEmpty) return;
    final id = _managedPoints.keys.last;
    if (await ctrl.layer_controller.removePointFromLayer(_pointLayerName, id) &&
        mounted) {
      setState(() {
        _managedPoints.remove(id);
        statusMessage = 'Removed point — total: ${_managedPoints.length}';
      });
    }
  }

  Future<void> _clearAllPoints() async {
    final ctrl = _controller;
    if (ctrl == null || _managedPoints.isEmpty) return;
    for (final id in _managedPoints.keys.toList()) {
      await ctrl.layer_controller.removePointFromLayer(_pointLayerName, id);
    }
    if (mounted) {
      setState(() {
        _managedPoints.clear();
        statusMessage = 'Cleared all points';
      });
    }
  }

  Future<void> _removeLastPolygon() async {
    final ctrl = _controller;
    if (ctrl == null || _managedPolygons.isEmpty) return;
    final id = _managedPolygons.keys.last;
    if (id == _selectedPolygonId) _deselectPolygon();
    if (await ctrl.layer_controller.removePolygonFromLayer(
          _polygonLayerName,
          id,
        ) &&
        mounted) {
      setState(() {
        _managedPolygons.remove(id);
        statusMessage = 'Removed polygon — total: ${_managedPolygons.length}';
      });
    }
  }

  Future<void> _clearAllPolygons() async {
    final ctrl = _controller;
    if (ctrl == null || _managedPolygons.isEmpty) return;
    if (_isEditing) _deselectPolygon();
    for (final id in _managedPolygons.keys.toList()) {
      await ctrl.layer_controller.removePolygonFromLayer(_polygonLayerName, id);
    }
    if (mounted) {
      setState(() {
        _managedPolygons.clear();
        statusMessage = 'Cleared all polygons';
      });
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final bool mapLocked = _isEditing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galileo Flutter Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions:
            _isEditing
                ? [
                  TextButton.icon(
                    onPressed: _deselectPolygon,
                    icon: const Icon(Icons.check_circle, color: Colors.white),
                    label: const Text(
                      'Done Editing',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ]
                : null,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color:
                _isEditing
                    ? const ui.Color(0xFFFFF9C4)
                    : _isDrawingPolygon
                    ? const ui.Color(0xFFE3F2FD)
                    : Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: $statusMessage',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isEditing
                            ? 'Map locked while editing · tap outside polygon to exit'
                            : _isDrawingPolygon
                            ? 'Keep tapping to add vertices — use the buttons to finish or cancel'
                            : 'Tap to add feature · drag to pan · +/− to zoom',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isEditing && !_isDrawingPolygon)
                  DropdownButton<String>(
                    value: _layerConfigString,
                    onChanged: (value) async {
                      if (value == null || value == _layerConfigString) return;
                      setState(() => _layerConfigString = value);
                      switch (value) {
                        case 'osm_tile_layer':
                          await _switchLayer(LayerConfig.osm());
                        case 'vector_tile_layer_1':
                          final style = await rootBundle.loadString(
                            'assets/vt_style.json',
                          );
                          if (!mounted) return;
                          await _switchLayer(
                            LayerConfig.vectorTiles(
                              urlTemplate: MAP_TILER_URL_TEMPLATE,
                              styleJson: style,
                            ),
                          );
                        case 'vector_tile_layer_2':
                          final style = await rootBundle.loadString(
                            'assets/simple_style.json',
                          );
                          if (!mounted) return;
                          await _switchLayer(
                            LayerConfig.vectorTiles(
                              urlTemplate: MAP_TILER_URL_TEMPLATE,
                              styleJson: style,
                            ),
                          );
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'osm_tile_layer',
                        child: Text('OSM Tile Layer'),
                      ),
                      DropdownMenuItem(
                        value: 'vector_tile_layer_1',
                        child: Text('Vector Tile Style 1'),
                      ),
                      DropdownMenuItem(
                        value: 'vector_tile_layer_2',
                        child: Text('Vector Tile Style 2'),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Draw-mode toolbar
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Draw mode:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                SegmentedButton<DrawMode>(
                  segments: const [
                    ButtonSegment(
                      value: DrawMode.point,
                      label: Text('Point'),
                      icon: Icon(Icons.location_on),
                    ),
                    ButtonSegment(
                      value: DrawMode.polygon,
                      label: Text('Polygon'),
                      icon: Icon(Icons.pentagon_outlined),
                    ),
                  ],
                  selected: {_drawMode},
                  onSelectionChanged: (s) {
                    if (_isEditing) _deselectPolygon();
                    if (_isDrawingPolygon) _cancelPendingPolygon();
                    setState(() => _drawMode = s.first);
                  },
                ),
                const Spacer(),
                CountChip(
                  icon: Icons.location_on,
                  color: const ui.Color(0xFFF44336),
                  count: _managedPoints.length,
                  label: 'pts',
                ),
                const SizedBox(width: 8),
                CountChip(
                  icon: Icons.pentagon_outlined,
                  color: const ui.Color(0xFF2196F3),
                  count: _managedPolygons.length,
                  label: 'poly',
                ),
              ],
            ),
          ),

          // Pending-polygon action bar
          if (_isDrawingPolygon)
            Container(
              color: const ui.Color(0xFFBBDEFB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.draw, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Drawing polygon — ${_pendingVertices.length} vertices',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo last vertex',
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed:
                        _pendingVertices.isNotEmpty
                            ? _undoLastPendingVertex
                            : null,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: _cancelPendingPolygon,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed:
                        _pendingVertices.length >= 3
                            ? _finishPendingPolygon
                            : null,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Finish Polygon'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

          // Map area
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: FutureBuilder(
                future: _controllerFuture,
                builder: (ctx, res) {
                  if (res.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (res.hasError)
                    return Center(child: Text('Error: ${res.error}'));
                  final (controller, err) = res.data!;
                  if (err != null) return Center(child: Text('Error: $err'));
                  if (_controller == null && controller != null) {
                    Future.microtask(() => _initManagedLayer(controller));
                  }

                  return Stack(
                    key: _mapStackKey,
                    fit: StackFit.expand,
                    children: [
                      // Base map.
                      AbsorbPointer(
                        absorbing: mapLocked || _isDrawingPolygon,
                        child: Builder(
                          builder:
                              (mapCtx) => Listener(
                                onPointerDown:
                                    (e) =>
                                        _pointerDownPosition = e.localPosition,
                                onPointerUp: (e) {
                                  final rb =
                                      mapCtx.findRenderObject() as RenderBox;
                                  final size = rb.size;
                                  final down = _pointerDownPosition;
                                  if (down != null &&
                                      (e.localPosition - down).distance <
                                          _tapThreshold) {
                                    _addFeatureAtScreenPos(
                                      e.localPosition.dx,
                                      e.localPosition.dy,
                                      size,
                                    );
                                  }
                                  _pointerDownPosition = null;
                                },
                                onPointerCancel:
                                    (_) => _pointerDownPosition = null,
                                child: GalileoMapWidget.fromController(
                                  key: ObjectKey(controller),
                                  controller: controller!,
                                  size: _kMapSize,
                                  config: _kMapConfig,
                                  layers: const [],
                                  enableKeyboard:
                                      !mapLocked && !_isDrawingPolygon,
                                  autoDispose: false,
                                  child: Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _isEditing
                                                ? 'Edit Controls:'
                                                : _isDrawingPolygon
                                                ? 'Drawing Polygon:'
                                                : 'Map Controls:',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (_isEditing) ...[
                                            const Text(
                                              '• Map locked (editing)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            const Text(
                                              '• Drag vertex to move',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Tap vertex to delete',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Tap ＋ to insert vertex',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Tap outside to exit edit',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ] else if (_isDrawingPolygon) ...[
                                            const Text(
                                              '• Tap to add vertex',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Need ≥3 to finish',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            const Text(
                                              '• Drag to pan while drawing',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Use toolbar to finish/cancel',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ] else ...[
                                            const Text(
                                              '• Tap to add feature',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Drag to pan',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Pinch to zoom',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• Arrow keys to pan',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                            const Text(
                                              '• +/- to zoom',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            'Points: ${_managedPoints.length}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                          Text(
                                            'Polygons: ${_managedPolygons.length}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),

                      // Pending-polygon preview overlay.
                      if (_isDrawingPolygon && _cachedViewport != null)
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown:
                              (e) => _pointerDownPosition = e.localPosition,
                          onPointerUp: (e) {
                            final down = _pointerDownPosition;
                            _pointerDownPosition = null;
                            if (down != null &&
                                (e.localPosition - down).distance <
                                    _tapThreshold) {
                              _addFeatureAtScreenPos(
                                e.localPosition.dx,
                                e.localPosition.dy,
                                _currentMapSize,
                              );
                            }
                          },
                          onPointerCancel: (_) => _pointerDownPosition = null,
                          child: CustomPaint(
                            painter: PendingPolygonPainter(
                              vertices: _pendingVertices,
                              viewport: _cachedViewport!,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),

                      // Edit-mode overlay.
                      if (_isEditing && _cachedViewport != null)
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _handleEditPointerDown,
                          onPointerMove: _handleEditPointerMove,
                          onPointerUp: _handleEditPointerUp,
                          child: CustomPaint(
                            painter: EditOverlayPainter(
                              vertices: _editingVertices,
                              viewport: _cachedViewport!,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Bottom controls
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      'Points:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady && _managedPoints.isNotEmpty)
                              ? _removeLastPoint
                              : null,
                      icon: const Icon(Icons.wrong_location, size: 16),
                      label: Text('Remove Last (${_managedPoints.length})'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady && _managedPoints.isNotEmpty)
                              ? _clearAllPoints
                              : null,
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear All'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.pentagon_outlined,
                      color: Colors.blue,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Polygons:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady &&
                                  _managedPolygons.isNotEmpty &&
                                  !_isEditing &&
                                  !_isDrawingPolygon)
                              ? _removeLastPolygon
                              : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      label: Text('Remove Last (${_managedPolygons.length})'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady &&
                                  _managedPolygons.isNotEmpty &&
                                  !_isEditing &&
                                  !_isDrawingPolygon)
                              ? _clearAllPolygons
                              : null,
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear All'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            () => showDialog(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('About'),
                    content: Text(
                      'Galileo Flutter Demo\n'
                      'Session ID: ${_controller?.sessionId ?? "none"}\n'
                      'Points on map: ${_managedPoints.length}\n'
                      'Polygons on map: ${_managedPolygons.length}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
            ),
        child: const Icon(Icons.info),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
