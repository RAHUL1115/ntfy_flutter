import 'package:flutter/material.dart';

class NtfyTopicIcon extends StatelessWidget {
  const NtfyTopicIcon({
    this.size = 35,
    this.color = const Color(0xff888888),
    super.key,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _NtfyTopicIconPainter(color),
  );
}

class _NtfyTopicIconPainter extends CustomPainter {
  const _NtfyTopicIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 50;
    canvas.save();
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeJoin = StrokeJoin.round;
    final bubble = Path()
      ..moveTo(7.8, 8.6)
      ..lineTo(43, 8.6)
      ..quadraticBezierTo(47.3, 8.6, 47.3, 12.8)
      ..lineTo(47.3, 37.6)
      ..quadraticBezierTo(47.3, 41.8, 43, 41.8)
      ..lineTo(12.2, 41.8)
      ..lineTo(3.5, 44.5)
      ..lineTo(3.5, 12.8)
      ..quadraticBezierTo(3.5, 8.6, 7.8, 8.6)
      ..close();
    canvas.drawPath(bubble, stroke);
    final mark = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(
      Path()
        ..moveTo(11.5, 18)
        ..lineTo(21.5, 23.5)
        ..lineTo(11.5, 29),
      mark,
    );
    canvas.drawLine(const Offset(28, 31), const Offset(39, 31), mark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NtfyTopicIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
