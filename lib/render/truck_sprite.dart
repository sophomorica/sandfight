import 'package:flutter/material.dart';

import '../theme/palette.dart';

class TruckSprite extends StatelessWidget {
  const TruckSprite({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(92, 52), painter: _TruckPainter());
  }
}

class _TruckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 10, size.width - 16, 26),
      const Radius.circular(4),
    );
    canvas.drawRRect(body, Paint()..color = Palette.metal);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(14, 14, 28, 16), const Radius.circular(2)),
      Paint()..color = const Color(0xFF6E675F),
    );
    canvas.drawCircle(Offset(26, 40), 7, Paint()..color = Palette.wheel);
    canvas.drawCircle(Offset(68, 40), 7, Paint()..color = Palette.wheel);
    canvas.drawCircle(Offset(26, 40), 3, Paint()..color = Palette.metal);
    canvas.drawCircle(Offset(68, 40), 3, Paint()..color = Palette.metal);
    canvas.drawCircle(Offset(74, 18), 3.5, Paint()..color = Palette.rust);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
