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

  const PolygonDrawOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final vp = ctrl.layerController?.viewportBounds;
            if (!ctrl.isDrawing || vp == null) {
              return const SizedBox.shrink();
            }

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown:
                  (e) => ctrl.handlePointerDown(e, constraints.biggest),
              onPointerMove:
                  (e) => ctrl.handlePointerMove(e, constraints.biggest),
              onPointerUp: (e) => ctrl.handlePointerUp(e, constraints.biggest),
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

  /// Called after any pointer event so the parent can call `setState`.
  final VoidCallback? onChanged;

  const PolygonEditOverlay({super.key, required this.editor, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ed = editor;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: ed,
          builder: (context, _) {
            final vp = ed.viewport;
            if (!ed.isActive || vp == null) {
              return const SizedBox.shrink();
            }
            final mapSize = constraints.biggest;
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => ed.handlePointerDown(e, mapSize),
              onPointerMove: (e) {
                ed.handlePointerMove(e, mapSize);
                onChanged?.call();
              },
              onPointerUp: (e) async {
                await ed.handlePointerUp(e, mapSize);
                onChanged?.call();
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
