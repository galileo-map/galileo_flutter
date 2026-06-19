import 'package:galileo_flutter/src/overlay/overlay_widget.dart';
import 'package:galileo_flutter/src/layer/controller.dart';
import 'package:galileo_flutter/src/feature/edit_controller.dart';
import 'package:galileo_flutter/src/rust/api/dart_types.dart';

import 'package:flutter/widgets.dart';

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

      final screenPos = overlay.loc.toScreen(height:mapSize.height,width:mapSize.width,vp:vp);

      final transformMatrix = Matrix4.identity();

      switch (overlay.type) {
        // Retains its exact pixel dimension profile regardless of map scaling changes
        case OverlayType.static:
          transformMatrix.translate(
            screenPos.x - (childSize.width / 2),
            screenPos.y - (childSize.height / 2),
          );
          break;

        // Dynamically changes its footprint on the screen to match map scale changes
        case OverlayType.relative:
          final scale = controller.zoomScale;

          transformMatrix.translate(screenPos.x, screenPos.y);

          transformMatrix.scale(scale);

          transformMatrix.translate(
            -childSize.width / 2,
            -childSize.height / 2,
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
