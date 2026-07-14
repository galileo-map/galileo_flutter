import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:logging/logging.dart';

final _log = Logger('FeatureLayerManager');

class FeatureLayerManager {
  static const _pointLayerName = 'managed-points';
  static const _polygonLayerName = 'managed-polygons';

  final LayerController layerController;
  final PolygonEditController _polygonEditController;
  final PolygonDrawController _polygonDrawController;

  final List<int> _pointIds = [];

  final Map<int, Polygon> _polygons = {};

  FeatureLayerManager({
    required this.layerController,
    required PolygonEditController polygonEditController,
    required PolygonDrawController polygonDrawController,
  }) : _polygonEditController = polygonEditController,
       _polygonDrawController = polygonDrawController;

  int get pointCount => _pointIds.length;
  int get polygonCount => _polygons.length;

  Map<int, Polygon> get polygons => Map.unmodifiable(_polygons);

  Future<void> initialize() async {
    await layerController.addPointFeatureLayer(_pointLayerName);
    await layerController.addPolygonFeatureLayer(
      _polygonLayerName,
      editor: _polygonEditController,
    );

    _polygonEditController.attach(this);
    _polygonDrawController.attach(this);
  }

  void dispose() {
    _polygonEditController.detach();
    _polygonDrawController.detach();
    _pointIds.clear();
    _polygons.clear();
  }

  // Handling primitive objects like Polygon and Points
  Future<void> addPoint(Point point) async {
    final id = await layerController.addPointToLayer(_pointLayerName, point);
    if (id >= 0) {
      _pointIds.add(id);
    } else {
      _log.warning('addPoint: rust returned invalid id $id');
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
      _log.warning('removeLastPoint: rust could not remove id $id');
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
      _log.warning('addPolygon: rust returned invalid id $id');
    }
  }

  Future<int> updatePolygon(int oldId, Polygon updated) async {
    final removed = await layerController.removePolygonFromLayer(
      _polygonLayerName,
      oldId,
    );
    if (!removed) {
      _log.warning('updatePolygon: could not remove old id $oldId');
    }
    _polygons.remove(oldId);

    final newId = await layerController.addPolygonToLayer(
      _polygonLayerName,
      updated,
    );
    if (newId >= 0) {
      _polygons[newId] = updated;
    } else {
      _log.warning('updatePolygon: rust returned invalid id $newId');
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
      _log.warning('removeLastPolygon: rust could not remove id $id');
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

  /// Whether the map should suppress panning while this editor is active.
  /// Override in subclasses that perform drag gestures (e.g. vertex drags).
  bool get shouldSuppressPan => false;

  void updateViewport(MapViewport viewport);
  void handlePointerDown(PointerDownEvent event, Size mapSize);
  void handlePointerMove(PointerMoveEvent event, Size mapSize);
  Future<void> handlePointerUp(PointerUpEvent event, Size mapSize);
  bool hitTestHandles(Offset localPosition, Size mapSize) => false;
}
