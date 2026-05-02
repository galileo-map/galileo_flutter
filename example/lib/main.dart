//ignore_for_file: constant_identifier_names

import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/galileo_map_controller.dart';

const MAP_TILER_API_KEY = 'nZPCm3UgMuXzMO7ifrjI';
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

/// Which feature type the tap gesture will place.
enum DrawMode { point, polygon }

(double lat, double lon) _mercatorToLatLon(double x, double y) {
  const earthRadius = 6378137.0;
  final lon = (x / earthRadius) * (180 / math.pi);
  final lat = (2 * math.atan(math.exp(y / earthRadius)) - math.pi / 2) *
      (180 / math.pi);
  return (lat, lon);
}

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
  LayerConfig _layerConfig = LayerConfig.osm();

  GalileoMapController? _controller;
  late Future<(GalileoMapController?, String?)> _controllerFuture;

  static const _pointLayerName   = 'points';
  static const _polygonLayerName = 'polygons';
  bool _layerReady = false;

  final Map<int, Point>   _managedPoints   = {};
  final Map<int, Polygon> _managedPolygons = {};

  DrawMode _drawMode = DrawMode.point;

  Offset? _pointerDownPosition;
  static const _tapThreshold = 10.0;

  @override
  void initState() {
    super.initState();
    _controllerFuture = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [LayerConfig.osm()],
    );
  }

  /// Dispose the current controller and create a fresh one with [newLayer].
  /// Any points/polygons added to the old controller are lost (they live in
  /// the controller's GPU context), so we clear the tracked collections too.
  Future<void> _switchLayer(LayerConfig newLayer) async {
    // Mark as not ready while we rebuild.
    setState(() {
      _layerReady   = false;
      statusMessage = 'Loading...';
    });

    // Tear down old controller.
    _controller?.dispose();
    _controller = null;
    _managedPoints.clear();
    _managedPolygons.clear();

    // Create a brand-new controller with the chosen base layer.
    final newFuture = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [newLayer],
    );

    setState(() => _controllerFuture = newFuture);

    // Wait for it, then init the feature layers.
    final (controller, err) = await newFuture;
    if (!mounted) return;
    if (err != null || controller == null) {
      setState(() => statusMessage = 'Error: ${err ?? "unknown"}');
      return;
    }
    await _initManagedLayer(controller);
  }

  Future<void> _initManagedLayer(GalileoMapController controller) async {
    setState(() => _controller = controller);
    await controller.addPointFeatureLayer(_pointLayerName);
    await controller.addPolygonFeatureLayer(_polygonLayerName);
    setState(() {
      _layerReady  = true;
      statusMessage = 'Tap map to add points';
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Add features
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _addFeatureAtScreenPos(double x, double y, Size size) async {
    final controller = _controller;
    if (controller == null || !_layerReady) return;

    final viewport = await controller.getViewport();
    if (viewport == null) return;

    final mx = viewport.xMin +
        (x / size.width)  * (viewport.xMax - viewport.xMin);
    final my = viewport.yMax -
        (y / size.height) * (viewport.yMax - viewport.yMin);

    final (lat, lon) = _mercatorToLatLon(mx, my);

    if (_drawMode == DrawMode.point) {
      await _addPoint(controller, lat, lon);
    } else {
      await _addPolygon(controller, lat, lon);
    }
  }

  Future<void> _addPoint(
      GalileoMapController controller, double lat, double lon) async {
    final point = Point(
      coordinate: (lat, lon),
      style: PointStyle(fillColor: Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
    );
    final id = await controller.addPointToLayer(_pointLayerName, point);
    if (mounted) {
      setState(() {
        _managedPoints[id] = point;
        statusMessage =
            'Point at (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}) '
            '— total: ${_managedPoints.length}';
      });
    }
  }

  Future<void> _addPolygon(
      GalileoMapController controller, double lat, double lon) async {
    final polygon = Polygon(
      points: [
        (lat,       lon),
        (lat + 0.3, lon + 0.8),
        (lat + 0.7, lon + 0.5),
        (lat + 0.5, lon),
      ],
      style: PolygonStyle(
        fillColor:   Color(r: 0.2, g: 0.5, b: 0.9, a: 0.8),
        strokeColor: Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        strokeWidth:  2.0,
        strokeOffset: 0.0,
      ),
    );
    final id = await controller.addPolygonToLayer(_polygonLayerName, polygon);
    if (mounted) {
      setState(() {
        _managedPolygons[id] = polygon;
        statusMessage =
            'Polygon at (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}) '
            '— total: ${_managedPolygons.length}';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Remove – points
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _removeLastPoint() async {
    final controller = _controller;
    if (controller == null || _managedPoints.isEmpty) return;

    final lastId = _managedPoints.keys.last;
    final removed =
        await controller.removePointFromLayer(_pointLayerName, lastId);
    if (removed && mounted) {
      setState(() {
        _managedPoints.remove(lastId);
        statusMessage = 'Removed point — total: ${_managedPoints.length}';
      });
    }
  }

  Future<void> _clearAllPoints() async {
    final controller = _controller;
    if (controller == null || _managedPoints.isEmpty) return;

    for (final id in _managedPoints.keys.toList()) {
      await controller.removePointFromLayer(_pointLayerName, id);
    }
    if (mounted) {
      setState(() {
        _managedPoints.clear();
        statusMessage = 'Cleared all points';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Remove – polygons
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _removeLastPolygon() async {
    final controller = _controller;
    if (controller == null || _managedPolygons.isEmpty) return;

    final lastId = _managedPolygons.keys.last;
    final removed =
        await controller.removePolygonFromLayer(_polygonLayerName, lastId);
    if (removed && mounted) {
      setState(() {
        _managedPolygons.remove(lastId);
        statusMessage = 'Removed polygon — total: ${_managedPolygons.length}';
      });
    }
  }

  Future<void> _clearAllPolygons() async {
    final controller = _controller;
    if (controller == null || _managedPolygons.isEmpty) return;

    for (final id in _managedPolygons.keys.toList()) {
      await controller.removePolygonFromLayer(_polygonLayerName, id);
    }
    if (mounted) {
      setState(() {
        _managedPolygons.clear();
        statusMessage = 'Cleared all polygons';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galileo Flutter Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // ── Status + tile-layer picker ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: $statusMessage',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to add feature · Drag to pan · +/- to zoom',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: _layerConfigString,
                  onChanged: (value) async {
                    if (value == null || value == _layerConfigString) return;
                    switch (value) {
                      case 'osm_tile_layer':
                        setState(() => _layerConfigString = 'osm_tile_layer');
                        await _switchLayer(LayerConfig.osm());
                        break;
                      case 'vector_tile_layer_1':
                        setState(() => _layerConfigString = 'vector_tile_layer_1');
                        final style = await rootBundle
                            .loadString('assets/vt_style.json');
                        if (!mounted) return;
                        await _switchLayer(LayerConfig.vectorTiles(
                          urlTemplate: MAP_TILER_URL_TEMPLATE,
                          styleJson:   style,
                        ));
                        break;
                      case 'vector_tile_layer_2':
                        setState(() => _layerConfigString = 'vector_tile_layer_2');
                        final style = await rootBundle
                            .loadString('assets/simple_style.json');
                        if (!mounted) return;
                        await _switchLayer(LayerConfig.vectorTiles(
                          urlTemplate: MAP_TILER_URL_TEMPLATE,
                          styleJson:   style,
                        ));
                        break;
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                        value: 'osm_tile_layer', child: Text('OSM Tile Layer')),
                    DropdownMenuItem(
                        value: 'vector_tile_layer_1',
                        child: Text('Vector Tile Style 1')),
                    DropdownMenuItem(
                        value: 'vector_tile_layer_2',
                        child: Text('Vector Tile Style 2')),
                  ],
                ),
              ],
            ),
          ),

          // ── Draw-mode toggle ───────────────────────────────────────────
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Draw mode:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                  onSelectionChanged: (s) =>
                      setState(() => _drawMode = s.first),
                ),
                const Spacer(),
                _CountChip(
                  icon: Icons.location_on,
                  color: const ui.Color(0xFFF44336),
                  count: _managedPoints.length,
                  label: 'pts',
                ),
                const SizedBox(width: 8),
                _CountChip(
                  icon: Icons.pentagon_outlined,
                  color: const ui.Color(0xFF2196F3),
                  count: _managedPolygons.length,
                  label: 'poly',
                ),
              ],
            ),
          ),

          // ── Map ────────────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration:
                  BoxDecoration(border: Border.all(color: Colors.grey)),
              child: FutureBuilder(
                future: _controllerFuture,
                builder: (ctx, res) {
                  if (res.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (res.hasError) {
                    return Center(child: Text('Error: ${res.error}'));
                  }
                  final (controller, err) = res.data!;
                  if (err != null) {
                    return Center(child: Text('Error: $err'));
                  }
                  // First build after the future resolves: init feature layers.
                  if (_controller == null && controller != null) {
                    Future.microtask(() => _initManagedLayer(controller));
                  }

                  return Builder(
                    builder: (ctx) {
                      return Listener(
                        onPointerDown: (e) =>
                            _pointerDownPosition = e.localPosition,
                        onPointerUp: (e) {
                          final renderBox =
                              ctx.findRenderObject() as RenderBox;
                          final size = renderBox.size;
                          final down = _pointerDownPosition;
                          if (down == null) return;
                          final delta = (e.localPosition - down).distance;
                          if (delta < _tapThreshold) {
                            _addFeatureAtScreenPos(
                              e.localPosition.dx,
                              e.localPosition.dy,
                              size,
                            );
                          }
                          _pointerDownPosition = null;
                        },
                        onPointerCancel: (_) => _pointerDownPosition = null,
                        child: GalileoMapWidget.fromController(
                          // Key on the controller identity so the widget
                          // is fully replaced when we switch layers.
                          key: ObjectKey(controller),
                          controller: controller!,
                          size: _kMapSize,
                          config: _kMapConfig,
                          // No layers override needed — the controller was
                          // already created with the correct base layer.
                          layers: const [],
                          enableKeyboard: true,
                          autoDispose: false,
                          child: Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Map Controls:',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  const Text('• Tap to add feature',
                                      style: TextStyle(fontSize: 10)),
                                  const Text('• Drag to pan',
                                      style: TextStyle(fontSize: 10)),
                                  const Text('• Pinch to zoom',
                                      style: TextStyle(fontSize: 10)),
                                  const Text('• Arrow keys to pan',
                                      style: TextStyle(fontSize: 10)),
                                  const Text('• +/- to zoom',
                                      style: TextStyle(fontSize: 10)),
                                  const SizedBox(height: 4),
                                  Text('Points: ${_managedPoints.length}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red)),
                                  Text('Polygons: ${_managedPolygons.length}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // ── Control panel – two independent rows ───────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Points row
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    const Text('Points:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_layerReady && _managedPoints.isNotEmpty)
                          ? _removeLastPoint
                          : null,
                      icon: const Icon(Icons.wrong_location, size: 16),
                      label: Text(
                          'Remove Last (${_managedPoints.length})'),
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_layerReady && _managedPoints.isNotEmpty)
                          ? _clearAllPoints
                          : null,
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear All'),
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Polygons row
                Row(
                  children: [
                    const Icon(Icons.pentagon_outlined,
                        color: Colors.blue, size: 18),
                    const SizedBox(width: 6),
                    const Text('Polygons:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady && _managedPolygons.isNotEmpty)
                              ? _removeLastPolygon
                              : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      label: Text(
                          'Remove Last (${_managedPolygons.length})'),
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.blue),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady && _managedPolygons.isNotEmpty)
                              ? _clearAllPolygons
                              : null,
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear All'),
                      style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.blue),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
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

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final ui.Color color;
  final int      count;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text('$count $label',
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
