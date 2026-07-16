import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Builds the widget shown for a single [PointCluster] bubble.
typedef ClusterBubbleBuilder =
    Widget Function(BuildContext context, PointCluster cluster);

/// Renders the clusters computed by a [PointClusterController] as tappable
/// bubbles positioned over the map, zooming in around a cluster when tapped.
///
/// Place this as a child in a [Stack] that covers the map area, alongside
/// [GalileoMapWidget].
class ClusterOverlay extends StatelessWidget {
  const ClusterOverlay({
    super.key,
    required this.controller,
    required this.mapController,
    this.bubbleBuilder,
    this.onClusterTap,
  });

  /// Supplies the points to cluster and the clustering radius.
  final PointClusterController controller;

  /// Map whose viewport drives cluster placement, and that gets zoomed in
  /// when a cluster bubble is tapped.
  final GalileoMapController mapController;

  /// Customizes how a cluster bubble is rendered. Defaults to
  /// [defaultBubbleBuilder].
  final ClusterBubbleBuilder? bubbleBuilder;

  /// Called in addition to the built-in zoom-in behavior whenever a cluster
  /// bubble is tapped, e.g. to update a status message.
  final void Function(PointCluster cluster)? onClusterTap;

  /// A circular bubble showing the point count, or a location pin for a
  /// single, unclustered point.
  static Widget defaultBubbleBuilder(
    BuildContext context,
    PointCluster cluster,
  ) {
    final isCluster = cluster.count > 1;
    final diameter = cluster.radius * 2;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (isCluster ? const Color(0xFF00BFA5) : const Color(0xFF1976D2))
            .withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child:
          isCluster
              ? Text(
                '${cluster.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              )
              : const Icon(Icons.location_on, color: Colors.white, size: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubble = bubbleBuilder ?? defaultBubbleBuilder;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return ListenableBuilder(
          listenable: Listenable.merge([
            controller,
            mapController.layerController,
          ]),
          builder: (context, _) {
            final vp = mapController.layerController.viewportBounds;
            if (vp == null || size.width <= 0 || size.height <= 0) {
              return const SizedBox.shrink();
            }

            final clusters = controller.computeClusters(size, vp);
            final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => controller.handlePointerDown(e, size, vp),
              onPointerUp:
                  (e) => controller.handlePointerUp(
                    e,
                    size,
                    vp,
                    mapController,
                    devicePixelRatio,
                    onClusterTap,
                  ),
              child: Stack(
                children: [
                  for (final cluster in clusters)
                    Positioned(
                      left: cluster.screenCenter.dx - cluster.radius,
                      top: cluster.screenCenter.dy - cluster.radius,
                      width: cluster.radius * 2,
                      height: cluster.radius * 2,
                      child: bubble(context, cluster),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
