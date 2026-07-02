import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/utils.dart';


class PolygonEditOverlayPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;

  const PolygonEditOverlayPainter({required this.vertices, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final pts = vertices.map((v) => geoToOffset(v, size, viewport)).toList();

    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x55FFEB3B)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFEB3B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(PolygonEditOverlayPainter old) =>
      old.vertices != vertices || old.viewport != viewport;
}

/// Draws the live preview of a polygon being drawn vertex-by-vertex.
/// Vertices are shown as blue dots; edges as dashed lines; if 3+ vertices
/// exist a translucent fill closes the shape.
class PendingPolygonPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;

  const PendingPolygonPainter({required this.vertices, required this.viewport});

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final pts = vertices.map((v) => geoToOffset(v, size, viewport)).toList();

    // Translucent fill + dashed border when closed (3+ pts).
    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x4400BFFF)
          ..style = PaintingStyle.fill,
      );
    }

    // Edge lines (open polyline).
    if (pts.length >= 2) {
      final edgePaint =
          Paint()
            ..color = const Color(0xFF0288D1)
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
      for (int i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(pts[i], pts[i + 1], edgePaint);
      }
      // Closing dashed preview line back to first vertex.
      final dashPaint =
          Paint()
            ..color = const Color(0x880288D1)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
      canvas.drawLine(pts.last, pts.first, dashPaint);
    }
  }

  @override
  bool shouldRepaint(PendingPolygonPainter old) =>
      old.vertices != vertices || old.viewport != viewport;
}

class CountChip extends StatelessWidget {
  const CountChip({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, color: color, size: 16),
      label: Text(
        '$count $label',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
