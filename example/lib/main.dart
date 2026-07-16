//ignore_for_file: constant_identifier_names

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

const MAP_TILER_API_KEY = '';
const MAP_TILER_URL_TEMPLATE =
    'https://api.maptiler.com/tiles/v3-openmaptiles/{z}/{x}/{y}.pbf?key=$MAP_TILER_API_KEY';

const _kMapSize = MapSize(width: 800, height: 600);
final _kMapConfig = MapInitConfig(
  backgroundColor: Color(0x1A1A0080).toGalileo(),
  enableMultisampling: true,
  latlon: GeoLocation(latitude: 0.0, longitude: 0.0),
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
  String _statusMessage = 'Loading...';
  String _layerConfigString = 'osm_tile_layer';

  GalileoMapController? _controller;
  late Future<(GalileoMapController?, String?)> _controllerFuture;

  FeatureLayerManager? _features;
  bool _layerReady = false;

  late final PolygonEditController _polygonEditor = PolygonEditController(
    onStatusMessage: (msg) => setState(() => _statusMessage = msg),
    onSelectionChanged: (_) => setState(() {}),
  );

  late final _polygonDrawer = PolygonDrawController(
    onStatusMessage: (msg) => setState(() => _statusMessage = msg),
  );

  DrawMode _drawMode = DrawMode.point;

  Offset? _pointerDownPosition;
  static const _tapThreshold = 10.0;

  bool _showClusters = false;
  late final _clusterController = PointClusterController(
    points: _generateClusterDemoPoints(),
  );

  @override
  void initState() {
    super.initState();
    _controllerFuture = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [LayerConfig.osm()],
    );
  }

  @override
  void dispose() {
    _polygonEditor.dispose();
    _polygonDrawer.dispose();
    _clusterController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _refreshViewport() async {
    final vp = await _controller?.getViewport();
    if (vp == null || !mounted) return;
    final bounds = MapViewport(
      xMin: vp.xMin,
      xMax: vp.xMax,
      yMin: vp.yMin,
      yMax: vp.yMax,
    );
    _polygonEditor.updateViewport(bounds);
    _polygonDrawer.updateViewport(bounds);
    _controller?.layerController.updateViewport(
      vp,
      _controller?.size ?? _kMapSize,
    );
  }

  Future<void> _switchLayer(LayerConfig newLayer) async {
    setState(() {
      _layerReady = false;
      _statusMessage = 'Loading...';
    });

    _controller?.dispose();
    _controller = null;
    _features?.dispose();
    _features = null;

    final f = GalileoMapController.create(
      size: _kMapSize,
      config: _kMapConfig,
      layers: [newLayer],
    );
    setState(() => _controllerFuture = f);

    final (ctrl, err) = await f;
    if (!mounted) return;
    if (err != null || ctrl == null) {
      setState(() => _statusMessage = 'Error: ${err ?? "unknown"}');
      return;
    }
    await _initManagedLayer(ctrl);
  }

  Future<void> _initManagedLayer(GalileoMapController ctrl) async {
    setState(() => _controller = ctrl);

    final manager = FeatureLayerManager(
      layerController: ctrl.layerController,
      polygonEditController: _polygonEditor,
      polygonDrawController: _polygonDrawer,
    );
    await manager.initialize();

    if (!mounted) return;
    setState(() {
      _features = manager;
      _layerReady = true;
      _statusMessage = 'Tap map to add features';
    });

    // Japan pin overlays
    final japanPins = [
      (
        loc: const GeoLocation(latitude: 43.06, longitude: 141.35),
        color: const Color(0xFF009688),
      ), // Sapporo
      (
        loc: const GeoLocation(latitude: 35.68, longitude: 139.69),
        color: const Color(0xFFE91E63),
      ), // Tokyo
      (
        loc: const GeoLocation(latitude: 36.29, longitude: 137.62),
        color: const Color(0xFF7E57C2),
      ), // Japanese Alps
      (
        loc: const GeoLocation(latitude: 35.01, longitude: 135.76),
        color: const Color(0xFFF57C00),
      ), // Kyoto
      (
        loc: const GeoLocation(latitude: 34.69, longitude: 135.50),
        color: const Color(0xFF1976D2),
      ), // Osaka
      (
        loc: const GeoLocation(latitude: 32.74, longitude: 129.87),
        color: const Color(0xFFAD1457),
      ), // Nagasaki
    ];

    for (final pin in japanPins) {
      ctrl.layerController.addOverlay(
        OverlayWidget.geo(
          loc: pin.loc,
          width: 36,
          height: 48,
          minZoom: 2.0,
          maxZoom: 10.0,
          child: _LocationPin(color: pin.color),
        ),
      );
    }

    await _refreshViewport();
  }

  Future<void> _addFeatureAtScreenPos(Offset off, Size size) async {
    final features = _features;
    if (features == null || !_layerReady) return;

    final viewport = await _controller?.getViewport();
    if (viewport == null || !mounted) return;

    final vp = MapViewport(
      xMin: viewport.xMin,
      xMax: viewport.xMax,
      yMin: viewport.yMin,
      yMax: viewport.yMax,
    );
    _polygonEditor.updateViewport(vp);
    _polygonDrawer.updateViewport(vp);

    if (_showClusters && _clusterController.wasClusterTappedOnPointerDown) {
      return;
    }

    final screenPos = ScreenLocation(x: off.dx, y: off.dy);
    final loc = screenPos.toGeographical(
      height: size.height,
      width: size.width,
      vp: vp,
    );

    if (_drawMode == DrawMode.point) {
      await _addPoint(features, loc);
      return;
    }

    if (_drawMode == DrawMode.polygon) {
      if (_polygonDrawer.isDrawing) {
        return;
      }
      final hit = await _polygonEditor.trySelectAt(off, size, vp);
      if (!hit && !_polygonEditor.wasActiveOnPointerDown) {
        _polygonDrawer.addVertex(loc);
      }
    }
  }

  Future<void> _addPoint(FeatureLayerManager features, GeoLocation loc) async {
    final point = Point(
      coordinate: loc,
      style: PointStyle(fillColor: Color(0xFF0000FF).toGalileo(), size: 8.0),
    );
    await features.addPoint(point);
    if (mounted) {
      setState(() {
        _statusMessage =
            'Point at (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}) '
            '— total: ${features.pointCount}';
      });
    }
  }

  Future<void> _removeLastPoint() async {
    final features = _features;
    if (features == null || features.pointCount == 0) return;
    await features.removeLastPoint();
    if (mounted) {
      setState(
        () => _statusMessage = 'Removed point — total: ${features.pointCount}',
      );
    }
  }

  Future<void> _clearAllPoints() async {
    final features = _features;
    if (features == null || features.pointCount == 0) return;
    await features.clearPoints();
    if (mounted) setState(() => _statusMessage = 'Cleared all points');
  }

  List<GeoLocation> _generateClusterDemoPoints() {
    final rand = Random(7);
    const hotspots = [
      GeoLocation(latitude: 40.71, longitude: -74.01), // New York
      GeoLocation(latitude: 51.51, longitude: -0.13), // London
      GeoLocation(latitude: 35.68, longitude: 139.69), // Tokyo
      GeoLocation(latitude: -33.87, longitude: 151.21), // Sydney
    ];
    final points = <GeoLocation>[];
    for (final hotspot in hotspots) {
      final count = 10 + rand.nextInt(10);
      for (var i = 0; i < count; i++) {
        final dLat = (rand.nextDouble() - 0.5) * 1.2;
        final dLon = (rand.nextDouble() - 0.5) * 1.2;
        points.add(
          GeoLocation(
            latitude: hotspot.latitude + dLat,
            longitude: hotspot.longitude + dLon,
          ),
        );
      }
    }
    return points;
  }

  void _toggleClusters(bool value) {
    setState(() {
      _showClusters = value;
      _statusMessage =
          value
              ? 'Cluster demo: tap a cluster to zoom in — ${_clusterController.points.length} points'
              : 'Tap map to add feature';
    });
  }

  void _onClusterTap(PointCluster cluster) {
    setState(
      () =>
          _statusMessage =
              cluster.count > 1
                  ? 'Zoomed into cluster of ${cluster.count} points'
                  : 'Zoomed to point',
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = _features;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galileo Flutter Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: $_statusMessage',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _polygonDrawer.isDrawing
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
                if (!_polygonDrawer.isDrawing)
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
                    if (_polygonDrawer.isDrawing) {
                      _polygonDrawer.cancel();
                    }
                    setState(() => _drawMode = s.first);
                  },
                ),
                const SizedBox(width: 16),
                const Icon(Icons.scatter_plot, size: 18),
                const SizedBox(width: 4),
                const Text(
                  'Clusters:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Switch(value: _showClusters, onChanged: _toggleClusters),
                const Spacer(),
                CountChip(
                  icon: Icons.location_on,
                  color: const Color(0xFFF44336),
                  count: features?.pointCount ?? 0,
                  label: 'pts',
                ),
                const SizedBox(width: 8),
                CountChip(
                  icon: Icons.pentagon_outlined,
                  color: const Color(0xFF2196F3),
                  count: features?.polygonCount ?? 0,
                  label: 'poly',
                ),
              ],
            ),
          ),

          if (_polygonDrawer.isDrawing)
            Container(
              color: const Color(0xFFBBDEFB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.draw, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Drawing polygon — ${_polygonDrawer.vertexCount} vertices',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo last vertex',
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed:
                        _polygonDrawer.isDrawing
                            ? () => _polygonDrawer.undoLastVertex()
                            : null,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    onPressed: () => _polygonDrawer.cancel(),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed:
                        _polygonDrawer.canFinish
                            ? () async {
                              await _polygonDrawer.finish(
                                PolygonStyle(
                                  fillColor:
                                      const Color(0x338FE6CC).toGalileo(),
                                  strokeColor:
                                      const Color(0xFFFFFFFF).toGalileo(),
                                  strokeWidth: 2.0,
                                  strokeOffset: 0.0,
                                ),
                              );
                              setState(() {});
                            }
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
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
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
                  if (err != null) return Center(child: Text('Error: $err'));
                  if (_controller == null && controller != null) {
                    Future.microtask(() => _initManagedLayer(controller));
                  }

                  return Builder(
                    builder:
                        (mapCtx) => Listener(
                          onPointerDown:
                              (e) => _pointerDownPosition = e.localPosition,
                          onPointerUp: (e) {
                            final rb = mapCtx.findRenderObject() as RenderBox;
                            final size = rb.size;
                            final down = _pointerDownPosition;
                            if (down != null &&
                                (e.localPosition - down).distance <
                                    _tapThreshold) {
                              _addFeatureAtScreenPos(e.localPosition, size);
                            }
                            _pointerDownPosition = null;
                          },
                          onPointerCancel: (_) => _pointerDownPosition = null,
                          child: GalileoMapWidget.fromController(
                            key: ObjectKey(controller),
                            controller: controller!,
                            config: _kMapConfig,
                            layers: const [],
                            enableKeyboard: true,
                            autoDispose: false,
                            onViewportChanged: (vp) async {
                              final bounds = MapViewport(
                                xMin: vp.xMin,
                                xMax: vp.xMax,
                                yMin: vp.yMin,
                                yMax: vp.yMax,
                              );
                              if (!mounted) return;
                              _polygonEditor.updateViewport(bounds);
                              _polygonDrawer.updateViewport(bounds);
                              _controller?.layerController.updateViewport(
                                vp,
                                _controller?.size ?? _kMapSize,
                              );
                            },
                            child: Stack(
                              children: [
                                PolygonDrawOverlay(controller: _polygonDrawer),
                                PolygonEditOverlay(
                                  editor: _polygonEditor,
                                  onChanged: () => setState(() {}),
                                ),
                                if (_showClusters)
                                  ClusterOverlay(
                                    controller: _clusterController,
                                    mapController: controller,
                                    onClusterTap: _onClusterTap,
                                  ),
                                Positioned(
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
                                        const SizedBox(height: 4),
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
                                        const SizedBox(height: 4),
                                        Text(
                                          'Points: ${features?.pointCount ?? 0}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                        Text(
                                          'Polygons: ${features?.polygonCount ?? 0}',
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
                              ],
                            ),
                          ),
                        ),
                  );
                },
              ),
            ),
          ),

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
                          (_layerReady && (features?.pointCount ?? 0) > 0)
                              ? _removeLastPoint
                              : null,
                      icon: const Icon(Icons.wrong_location, size: 16),
                      label: Text('Remove Last (${features?.pointCount ?? 0})'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady && (features?.pointCount ?? 0) > 0)
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
                                  (features?.polygonCount ?? 0) > 0 &&
                                  _polygonDrawer.isDrawing != true)
                              ? () async {
                                await features?.removeLastPolygon();
                                setState(() {});
                              }
                              : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      label: Text(
                        'Remove Last (${features?.polygonCount ?? 0})',
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_layerReady &&
                                  (features?.polygonCount ?? 0) > 0 &&
                                  _polygonDrawer.isDrawing != true)
                              ? () async {
                                await features?.clearPolygons();
                                setState(() {});
                              }
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
                      'Points on map: ${features?.pointCount ?? 0}\n'
                      'Polygons on map: ${features?.polygonCount ?? 0}',
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
}

class _LocationPin extends StatelessWidget {
  const _LocationPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 48,
      child: CustomPaint(painter: _PinPainter(color: color)),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;

    final radius = w * 0.46;
    final centerY = radius + 2;

    final holePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, centerY), radius * 0.38, holePaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, centerY), radius * 0.18, dotPaint);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color;
}
