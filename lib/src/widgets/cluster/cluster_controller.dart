import 'package:flutter/widgets.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart' show UserEvent;

/// A group of nearby points, formed by [PointClusterController.computeClusters]
/// because their projected screen positions fell within the cluster radius
/// of one another.
class PointCluster {
  const PointCluster({
    required this.geoCenter,
    required this.screenCenter,
    required this.points,
  });

  /// Centroid of [points] in geographic coordinates.
  final GeoLocation geoCenter;

  /// Centroid of the member points' projected screen positions.
  final Offset screenCenter;

  /// The points grouped into this cluster.
  final List<GeoLocation> points;

  /// Number of points in this cluster.
  int get count => points.length;

  /// Suggested on-screen radius for rendering/hit-testing this cluster,
  /// scaled up as more points are grouped together.
  double get radius =>
      count == 1 ? 10.0 : (14.0 + count * 0.8).clamp(14.0, 32.0);
}

class _MutableCluster {
  _MutableCluster(GeoLocation firstPoint, this.screenCenter)
    : points = [firstPoint];

  final List<GeoLocation> points;
  Offset screenCenter;

  void add(GeoLocation point, Offset offset) {
    final n = points.length;
    points.add(point);
    screenCenter = Offset(
      (screenCenter.dx * n + offset.dx) / (n + 1),
      (screenCenter.dy * n + offset.dy) / (n + 1),
    );
  }

  PointCluster toCluster() {
    var lat = 0.0;
    var lon = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return PointCluster(
      geoCenter: GeoLocation(
        latitude: lat / points.length,
        longitude: lon / points.length,
      ),
      screenCenter: screenCenter,
      points: List.unmodifiable(points),
    );
  }
}

/// Groups a set of [GeoLocation] points into on-screen clusters and drives
/// "tap a cluster to zoom in" interactions.
///
/// Pair with [ClusterOverlay] to render the clusters as tappable bubbles.
class PointClusterController extends ChangeNotifier {
  PointClusterController({
    List<GeoLocation> points = const [],
    this.clusterRadiusPx = 45.0,
  }) : _points = List.of(points);

  List<GeoLocation> _points;

  /// Points within this many screen pixels of a cluster's running centroid
  /// are grouped into that cluster.
  final double clusterRadiusPx;

  /// Unmodifiable view of the points managed by this controller.
  List<GeoLocation> get points => List.unmodifiable(_points);

  Offset? _pointerDownPos;
  PointCluster? _tappedCluster;
  bool _wasClusterTappedOnPointerDown = false;

  /// True if a cluster bubble was hit during the current/most-recent pointer down event.
  bool get wasClusterTappedOnPointerDown => _wasClusterTappedOnPointerDown;

  void handlePointerDown(PointerDownEvent event, Size mapSize, MapViewport vp) {
    final clusters = computeClusters(mapSize, vp);
    _tappedCluster = null;
    _wasClusterTappedOnPointerDown = false;
    _pointerDownPos = event.localPosition;

    for (final cluster in clusters) {
      if ((cluster.screenCenter - event.localPosition).distance <=
          cluster.radius) {
        _tappedCluster = cluster;
        _wasClusterTappedOnPointerDown = true;
        break;
      }
    }
  }

  Future<void> handlePointerUp(
    PointerUpEvent event,
    Size mapSize,
    MapViewport vp,
    GalileoMapController mapController,
    double devicePixelRatio,
    void Function(PointCluster)? onClusterTap,
  ) async {
    final cluster = _tappedCluster;
    final down = _pointerDownPos;
    final isTap =
        cluster != null &&
        down != null &&
        (event.localPosition - down).distance < 10.0;

    _pointerDownPos = null;
    _tappedCluster = null;

    if (isTap) {
      onClusterTap?.call(cluster);
      await zoomToCluster(
        mapController,
        cluster,
        devicePixelRatio: devicePixelRatio,
      );
    }
  }

  void setPoints(List<GeoLocation> points) {
    _points = List.of(points);
    notifyListeners();
  }

  void addPoint(GeoLocation point) {
    _points.add(point);
    notifyListeners();
  }

  void clear() {
    _points.clear();
    notifyListeners();
  }

  /// Greedily groups points whose projected screen positions (given the
  /// current [size] and [vp]) fall within [clusterRadiusPx] of an existing
  /// cluster's running centroid. Points projected outside the viewport
  /// (plus a margin) are skipped.
  List<PointCluster> computeClusters(Size size, MapViewport vp) {
    final groups = <_MutableCluster>[];
    final screenPoints = GeoLocation.pointsToScreen(
      points: _points,
      height: size.height,
      width: size.width,
      vp: vp,
    );
    for (var i = 0; i < _points.length; i++) {
      final point = _points[i];
      final screen = screenPoints[i];
      final offset = Offset(screen.x, screen.y);
      if (offset.dx < -clusterRadiusPx ||
          offset.dx > size.width + clusterRadiusPx ||
          offset.dy < -clusterRadiusPx ||
          offset.dy > size.height + clusterRadiusPx) {
        continue;
      }

      _MutableCluster? match;
      for (final group in groups) {
        if ((group.screenCenter - offset).distance <= clusterRadiusPx) {
          match = group;
          break;
        }
      }
      if (match != null) {
        match.add(point, offset);
      } else {
        groups.add(_MutableCluster(point, offset));
      }
    }
    return [for (final group in groups) group.toCluster()];
  }

  /// Zooms [controller]'s map in around [cluster]'s screen position, using
  /// the same zoom-around-point mechanism as the built-in +/- keyboard
  /// shortcuts, so the cluster's member points spread apart on screen.
  Future<void> zoomToCluster(
    GalileoMapController controller,
    PointCluster cluster, {
    double devicePixelRatio = 1.0,
    double zoomFactor = 0.55,
    int? steps,
  }) async {
    final anchor = Point2(
      x: cluster.screenCenter.dx * devicePixelRatio,
      y: cluster.screenCenter.dy * devicePixelRatio,
    );
    final effectiveSteps =
        steps ?? (cluster.count == 1 ? 1 : (cluster.count > 12 ? 4 : 3));
    for (var i = 0; i < effectiveSteps; i++) {
      await controller.handleEvent(UserEvent.zoom(zoomFactor, anchor));
    }
  }
}
