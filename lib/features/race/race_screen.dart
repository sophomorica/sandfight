import 'package:flutter/material.dart';

import '../../draw/race.dart';
import '../../theme/palette.dart';
import '../zen/sand_stage.dart';

class RaceScreen extends StatelessWidget {
  const RaceScreen({
    super.key,
    required this.glyph,
    required this.clock,
    required this.onStroke,
    required this.onLeave,
    this.place,
  });

  final Glyph glyph;
  final ClockFace clock;
  final Place? place;
  final void Function(Stroke stroke) onStroke;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final place = this.place;
    return Scaffold(
      backgroundColor: Palette.pit,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    glyph.name,
                    style: const TextStyle(
                      color: Palette.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _clockLabel(clock),
                    style: const TextStyle(color: Palette.dust, fontSize: 16),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onLeave,
                    child: const Text(
                      'Leave',
                      style: TextStyle(color: Palette.dust, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            if (place != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _placeLabel(place),
                  style: const TextStyle(
                    color: Palette.glow,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SandStage(onStroke: (points) => onStroke(Stroke(points))),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _GlyphOutline(glyph),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _clockLabel(ClockFace clock) {
  return switch (clock) {
    Counting(:final remainingMs) => _seconds(remainingMs),
    Locked(:final elapsedMs) => elapsedMs == null ? '' : _seconds(elapsedMs),
  };
}

String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

String _placeLabel(Place place) {
  return switch (place) {
    Place.ahead => 'Ahead',
    Place.behind => 'Behind',
    Place.tied => 'Draw',
  };
}

class _GlyphOutline extends CustomPainter {
  const _GlyphOutline(this.glyph);

  final Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.shortestSide * 0.46;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Palette.ink.withValues(alpha: 0.72);
    switch (glyph) {
      case Glyph.circle:
        canvas.drawCircle(center, side / 2, paint);
      case Glyph.square:
        canvas.drawRect(
          Rect.fromCenter(center: center, width: side, height: side),
          paint,
        );
      case Glyph.triangle:
        final path = Path()
          ..moveTo(center.dx, center.dy - side / 2)
          ..lineTo(center.dx + side / 2, center.dy + side / 2)
          ..lineTo(center.dx - side / 2, center.dy + side / 2)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphOutline oldDelegate) =>
      oldDelegate.glyph != glyph;
}
