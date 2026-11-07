import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Custom line icons drawn to match the Figma "Icons" frame.
class CgIcon extends StatelessWidget {
  const CgIcon(this.type, {super.key, this.size = 28, this.color = AppColors.navy, this.strokeWidth});
  final CgIconType type;
  final double size;
  final Color color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _IconPainter(type, color, strokeWidth ?? size * 0.075)),
      );
}

enum CgIconType { home, scan, gem, settings, emptyBox }

class _IconPainter extends CustomPainter {
  _IconPainter(this.type, this.color, this.stroke);
  final CgIconType type;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width, h = s.height;
    switch (type) {
      case CgIconType.home:
        final path = Path()
          ..moveTo(w * 0.18, h * 0.42)
          ..lineTo(w * 0.5, h * 0.12)
          ..lineTo(w * 0.82, h * 0.42)
          ..lineTo(w * 0.82, h * 0.78)
          ..quadraticBezierTo(w * 0.82, h * 0.88, w * 0.72, h * 0.88)
          ..lineTo(w * 0.28, h * 0.88)
          ..quadraticBezierTo(w * 0.18, h * 0.88, w * 0.18, h * 0.78)
          ..close();
        canvas.drawPath(path, p);
        canvas.drawRect(Rect.fromLTWH(w * 0.6, h * 0.66, w * 0.1, h * 0.1), Paint()..color = color);
      case CgIconType.scan:
        final c = w * 0.2; // bracket length
        final m = w * 0.08; // margin
        final r = w * 0.08;
        void bracket(Offset corner, double dx, double dy) {
          final path = Path()
            ..moveTo(corner.dx, corner.dy + dy * c)
            ..lineTo(corner.dx, corner.dy + dy * r)
            ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * r, corner.dy)
            ..lineTo(corner.dx + dx * c, corner.dy);
          canvas.drawPath(path, p);
        }

        bracket(Offset(m, m), 1, 1);
        bracket(Offset(w - m, m), -1, 1);
        bracket(Offset(m, h - m), 1, -1);
        bracket(Offset(w - m, h - m), -1, -1);
        canvas.drawLine(Offset(w * 0.12, h * 0.5), Offset(w * 0.88, h * 0.5), p);
        // crystal / rock outline: top arc with a small notch, bottom arc
        final top = Path()
          ..moveTo(w * 0.3, h * 0.44)
          ..quadraticBezierTo(w * 0.32, h * 0.26, w * 0.52, h * 0.25)
          ..quadraticBezierTo(w * 0.56, h * 0.33, w * 0.62, h * 0.3)
          ..quadraticBezierTo(w * 0.7, h * 0.33, w * 0.7, h * 0.44);
        canvas.drawPath(top, p);
        canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h * 0.56), width: w * 0.42, height: h * 0.34), 0.25,
            math.pi - 0.5, false, p);
      case CgIconType.gem:
        final a = Offset(w * 0.5, h * 0.08);
        final l = Offset(w * 0.1, h * 0.58);
        final rr = Offset(w * 0.9, h * 0.58);
        final b = Offset(w * 0.46, h * 0.92);
        final mid = Offset(w * 0.56, h * 0.52);
        canvas.drawPath(Path()..addPolygon([a, rr, b, l], true), p);
        canvas.drawLine(a, mid, p);
        canvas.drawLine(l, mid, p);
        canvas.drawLine(rr, mid, p);
        canvas.drawLine(b, mid, p);
      case CgIconType.settings:
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final ang = math.pi / 6 + i * math.pi / 3;
          final pt = Offset(w / 2 + w * 0.42 * math.cos(ang), h / 2 + h * 0.42 * math.sin(ang));
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        path.close();
        canvas.drawPath(path, p);
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.16, p);
      case CgIconType.emptyBox:
        final top = [Offset(w * 0.15, h * 0.38), Offset(w * 0.5, h * 0.24), Offset(w * 0.85, h * 0.38), Offset(w * 0.5, h * 0.52)];
        canvas.drawPath(Path()..addPolygon(top, true), p);
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.15, h * 0.38)
              ..lineTo(w * 0.15, h * 0.72)
              ..lineTo(w * 0.5, h * 0.88)
              ..lineTo(w * 0.85, h * 0.72)
              ..lineTo(w * 0.85, h * 0.38),
            p);
        canvas.drawLine(Offset(w * 0.5, h * 0.52), Offset(w * 0.5, h * 0.88), p);
        // sparkle lines above the box
        canvas.drawLine(Offset(w * 0.5, h * 0.04), Offset(w * 0.5, h * 0.14), p);
        canvas.drawLine(Offset(w * 0.3, h * 0.08), Offset(w * 0.36, h * 0.16), p);
        canvas.drawLine(Offset(w * 0.7, h * 0.08), Offset(w * 0.64, h * 0.16), p);
    }
  }

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.type != type || old.color != color || old.stroke != stroke;
}
