import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';

/// Overlay widget for drawing a new polygon.
///
/// Handles tap detection internally, converts screen coordinates to lat/lon
/// and calls [PolygonDrawController.addVertex].
/// Renders the live preview via [PendingPolygonPainter].
///
/// Place this as a child in a [Stack] that covers the map area.
class PolygonDrawOverlay extends StatefulWidget {
  final PolygonDrawController? controller;

  const PolygonDrawOverlay({super.key, required this.controller});

  @override
  State<PolygonDrawOverlay> createState() => _PolygonDrawOverlayState();
}

class _PolygonDrawOverlayState extends State<PolygonDrawOverlay> {
  static const _tapThreshold = 10.0;
  Offset? _pointerDownPosition;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    if (ctrl == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final vp = ctrl.layerController.viewportBounds;
        if (!ctrl.isDrawing || vp == null) {
          return const SizedBox.shrink();
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _pointerDownPosition = e.localPosition,
          onPointerUp: (e) {
            final down = _pointerDownPosition;
            _pointerDownPosition = null;
            if (down != null &&
                (e.localPosition - down).distance < _tapThreshold) {
              final rb = context.findRenderObject() as RenderBox;
              final size = rb.size;
              final screenPos = ScreenLocation(
                x: e.localPosition.dx,
                y: e.localPosition.dy,
              ).toGeographical(height: size.height, width: size.width, vp: vp);
              ctrl.addVertex(screenPos);
            }
          },
          onPointerCancel: (_) => _pointerDownPosition = null,
          child: CustomPaint(
            painter: PendingPolygonPainter(
              vertices: ctrl.pendingVertices,
              viewport: vp,
            ),
            child: const SizedBox.expand(),
          ),
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
  final PolygonEditController? editor;

  /// Called after any pointer event so the parent can call `setState`.
  final VoidCallback? onChanged;

  const PolygonEditOverlay({super.key, required this.editor, this.onChanged});

  Size _mapSize(BuildContext context) {
    final rb = context.findRenderObject() as RenderBox?;
    return rb?.size ?? const Size(800, 600);
  }

  @override
  Widget build(BuildContext context) {
    final ed = editor;
    if (ed == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: ed,
      builder: (context, _) {
        final vp = ed.viewport;
        if (!ed.isActive || vp == null) {
          return const SizedBox.shrink();
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => ed.handlePointerDown(e, _mapSize(context)),
          onPointerMove: (e) {
            ed.handlePointerMove(e, _mapSize(context));
            onChanged?.call();
          },
          onPointerUp: (e) async {
            await ed.handlePointerUp(e, _mapSize(context));
            onChanged?.call();
          },
          child: CustomPaint(
            painter: EditOverlayPainter(
              vertices: ed.editingVertices,
              viewport: vp,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
