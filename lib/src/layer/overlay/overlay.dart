import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/utils.dart';
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

        return ClipRect(
          child: Flow(
            delegate: MapOverlayFlowDelegate(
              controller: controller,
              mapSize: mapSize,
              overlays: overlays,
            ),
            children: overlays,
          ),
        );
      },
    );
  }
}

class MapOverlayFlowDelegate extends FlowDelegate {
  final LayerController controller;
  final Size mapSize;
  final List<OverlayWidget> overlays;

  MapOverlayFlowDelegate({
    required this.controller,
    required this.mapSize,
    required this.overlays,
  }) : super(repaint: controller.viewportListenable);

  // Should constrain the size of the child with their own height and width
  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints.loose(Size(overlays[i].width, overlays[i].height));
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final vp = controller.viewportBounds;
    if (vp == null) return;
    final zoomScale = controller.zoomScale;

    for (int i = 0; i < overlays.length; i++) {
      final overlay = overlays[i];

      // Skip overlays outside their zoom visibility range.
      if (!overlay.isVisibleAt(zoomScale)) continue;

      final childSize =
          context.getChildSize(i) ?? Size(overlay.width, overlay.height);

      final screenPos = geoToOffset(overlay.loc, mapSize, vp);
      final halfWidth = childSize.width / 2;
      final halfHeight = childSize.height / 2;

      // Skip overlays entirely outside the viewport; the flow clips anyway,
      // so painting them only wastes raster time.
      if (screenPos.dx + halfWidth < 0 ||
          screenPos.dx - halfWidth > mapSize.width ||
          screenPos.dy + halfHeight < 0 ||
          screenPos.dy - halfHeight > mapSize.height) {
        continue;
      }

      final transformMatrix = Matrix4.translationValues(
        screenPos.dx - halfWidth,
        screenPos.dy - halfHeight,
        0,
      );

      context.paintChild(i, transform: transformMatrix);
    }
  }

  @override
  bool shouldRepaint(covariant MapOverlayFlowDelegate oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.mapSize != mapSize ||
        oldDelegate.overlays != overlays;
  }
}
