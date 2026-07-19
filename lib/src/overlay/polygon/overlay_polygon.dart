import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Overlay widget for drawing a new polygon.
///
/// Handles tap detection internally, converts screen coordinates to lat/lon
/// and calls [PolygonDrawController.addVertex].
/// Renders the live preview via [PendingPolygonPainter].
///
/// Place this as a child in a [Stack] that covers the map area.
class PolygonDrawOverlay extends StatelessWidget {
  final PolygonDrawController controller;
  final MapInteractionController? interactionController;

  const PolygonDrawOverlay({
    super.key,
    required this.controller,
    this.interactionController,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final layerController = ctrl.layerController;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable:
              layerController == null
                  ? ctrl
                  : Listenable.merge([ctrl, layerController.viewportChanges]),
          builder: (context, _) {
            final vp = ctrl.layerController?.viewportBounds;
            if (!ctrl.isDrawing || vp == null) {
              return const SizedBox.shrink();
            }

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                interactionController?.consume(e.pointer);
                ctrl.handlePointerDown(e, constraints.biggest, vp);
              },
              onPointerMove:
                  (e) => ctrl.handlePointerMove(e, constraints.biggest, vp),
              onPointerUp:
                  (e) => ctrl.handlePointerUp(e, constraints.biggest, vp),
              onPointerCancel:
                  (e) => ctrl.handlePointerCancel(e, constraints.biggest),
              child: CustomPaint(
                painter: PendingPolygonPainter(
                  vertices: ctrl.pendingVertices,
                  viewport: vp,
                  draggingVertexIndex: ctrl.draggingVertexIndex,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        );
      },
    );
  }
}

/// Overlay widget for editing an existing polygon.
///
/// Delegates pointer events to [PolygonEditController] for vertex drag, delete,
/// and midpoint insertion. Renders via [EditOverlayPainter].
///
/// Place this as a child in a [Stack] that covers the map area.
class PolygonEditOverlay extends StatelessWidget {
  final PolygonEditController editor;
  final MapInteractionController? interactionController;

  /// Called after a pointer-up edit action has completed.
  final VoidCallback? onSubmit;

  const PolygonEditOverlay({
    super.key,
    required this.editor,
    this.interactionController,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final ed = editor;
    final layerController = ed.layerController;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable:
              layerController == null
                  ? ed
                  : Listenable.merge([ed, layerController.viewportChanges]),
          builder: (context, _) {
            final vp = ed.layerController?.viewportBounds;
            if (!ed.isActive || vp == null) {
              return const SizedBox.shrink();
            }
            final mapSize = constraints.biggest;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                interactionController?.consume(e.pointer);
                ed.handlePointerDown(e, mapSize, vp);
              },
              onPointerMove: (e) => ed.handlePointerMove(e, mapSize, vp),
              onPointerUp: (e) async {
                await ed.handlePointerUp(e, mapSize, vp);
                onSubmit?.call();
              },
              child: CustomPaint(
                painter: PolygonEditOverlayPainter(
                  vertices: ed.editingVertices,
                  viewport: vp,
                  draggingVertexIndex: ed.draggingVertexIndex,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        );
      },
    );
  }
}
