import 'package:flutter/material.dart';
import 'package:galileo_flutter/galileo_flutter.dart';
import 'package:galileo_flutter/src/utils.dart';

const _kVertexR = 11.0;
const _kMidpointR = 8.0;

const _kHandleRed = Color(0xFFE53935);

Paint _fillPaint(Color c) =>
    Paint()
      ..color = c
      ..style = PaintingStyle.fill;
Paint _strokePaint(Color c, double w) =>
    Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

final Paint _sharedPaint = Paint();

void _drawHandle(
  Canvas canvas,
  Offset center,
  double r,
  Color bg, {
  Color border = Colors.white,
  double borderWidth = 2.0,
}) {
  _sharedPaint.style = PaintingStyle.fill;
  _sharedPaint.color = bg;
  canvas.drawCircle(center, r, _sharedPaint);

  _sharedPaint.style = PaintingStyle.stroke;
  _sharedPaint.color = border;
  _sharedPaint.strokeWidth = borderWidth;
  canvas.drawCircle(center, r, _sharedPaint);
}

/// Draws a "+" symbol at [center] with arm length [arm].
void _drawPlus(Canvas canvas, Offset center, double arm, Color color) {
  final p = _strokePaint(color, 2.0)..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(center.dx - arm, center.dy),
    Offset(center.dx + arm, center.dy),
    p,
  );
  canvas.drawLine(
    Offset(center.dx, center.dy - arm),
    Offset(center.dx, center.dy + arm),
    p,
  );
}

class PolygonEditOverlayPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;

  final int? draggingVertexIndex;

  const PolygonEditOverlayPainter({
    required this.vertices,
    required this.viewport,
    this.draggingVertexIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final pts = vertices.map((v) => geoToOffset(v, size, viewport)).toList();

    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(path, _fillPaint(const Color(0x22FFFFFF)));
      canvas.drawPath(path, _strokePaint(const Color(0xCCFFFFFF), 1.5));
    } else if (pts.length == 2) {
      canvas.drawLine(
        pts[0],
        pts[1],
        _strokePaint(const Color(0xCCFFFFFF), 1.5),
      );
    }

    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

      _drawHandle(canvas, mid, _kMidpointR, _kHandleRed);
      _drawPlus(canvas, mid, _kMidpointR * 0.5, Colors.white);
    }

    for (int i = 0; i < pts.length; i++) {
      final pt = pts[i];
      final isDragging = i == draggingVertexIndex;

      _drawHandle(
        canvas,
        pt,
        _kVertexR,
        isDragging ? Colors.white : _kHandleRed,
        border: isDragging ? _kHandleRed : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(PolygonEditOverlayPainter old) =>
      old.vertices != vertices ||
      old.viewport != viewport ||
      old.draggingVertexIndex != draggingVertexIndex;
}

class PendingPolygonPainter extends CustomPainter {
  final List<GeoLocation> vertices;
  final MapViewport viewport;
  final int? draggingVertexIndex;

  const PendingPolygonPainter({
    required this.vertices,
    required this.viewport,
    this.draggingVertexIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final pts = vertices.map((v) => geoToOffset(v, size, viewport)).toList();

    if (pts.length >= 3) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(path, _fillPaint(const Color(0x4400BFFF)));
    }

    if (pts.length >= 2) {
      final edgePaint = _strokePaint(const Color(0xFF0288D1), 2.0);
      for (int i = 0; i < pts.length - 1; i++) {
        canvas.drawLine(pts[i], pts[i + 1], edgePaint);
      }
      canvas.drawLine(
        pts.last,
        pts.first,
        _strokePaint(const Color(0x880288D1), 1.5),
      );
    }

    for (int i = 0; i < pts.length; i++) {
      final pt = pts[i];
      final isDragging = i == draggingVertexIndex;

      _drawHandle(
        canvas,
        pt,
        _kVertexR,
        isDragging ? Colors.white : _kHandleRed,
        border: isDragging ? _kHandleRed : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(PendingPolygonPainter old) =>
      old.vertices != vertices ||
      old.viewport != viewport ||
      old.draggingVertexIndex != draggingVertexIndex;
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
