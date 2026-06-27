import 'package:galileo_flutter/src/overlay/overlay_widget.dart';
import 'package:galileo_flutter/src/layer/controller.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

class MapOverlayLayer extends StatelessWidget {
  final LayerController controller;
  final List<OverlayWidget> overlays;

  const MapOverlayLayer({
    super.key,
    required this.controller,
    required this.overlays,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Flow(
          delegate: MapOverlayFlowDelegate(
            controller: controller,
            mapSize: mapSize,
            overlays: overlays,
          ),
          children: overlays,
        );
      },
    );
  }
}

class MapOverlayFlowDelegate extends FlowDelegate {
  final LayerController controller;
  final Size mapSize;
  final List<OverlayWidget> overlays;
  final MapViewport? viewportBounds;
  final double zoomScale;

  MapOverlayFlowDelegate({
    required this.controller,
    required this.mapSize,
    required this.overlays,
  }) : viewportBounds = controller.viewportBounds,
       zoomScale = controller.zoomScale,
       super(repaint: controller);

  // Should constrain the size of the child with their own height and width
  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints.loose(Size(overlays[i].width, overlays[i].height));
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final vp = controller.viewportBounds;
    if (vp == null) return;

    for (int i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];

      final childSize =
          context.getChildSize(i) ?? Size(overlay.width, overlay.height);

      final transformMatrix = Matrix4.identity();

      switch (overlay.type) {
        case OverlayType.static:
          final loc = overlay.loc as ScreenLocation;
          final screenPos = loc;
          transformMatrix.translateByVector3(
            Vector3(screenPos.x, screenPos.y, 0),
          );
          break;
        case OverlayType.relative:
          final loc = overlay.loc as GeoLocation;
          final screenPos = loc.toScreen(
            height: mapSize.height,
            width: mapSize.width,
            vp: vp,
          );
          transformMatrix.translateByVector3(
            Vector3(
              screenPos.x - (childSize.width / 2),
              screenPos.y - (childSize.height / 2),
              0,
            ),
          );
          break;
      }

      context.paintChild(i, transform: transformMatrix);
    }
  }

  @override
  bool shouldRepaint(covariant MapOverlayFlowDelegate oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.mapSize != mapSize ||
        oldDelegate.overlays != overlays ||
        oldDelegate.viewportBounds != viewportBounds ||
        oldDelegate.zoomScale != zoomScale;
  }
}
