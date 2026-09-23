import 'package:flutter/material.dart';

import '../game/sand_grid.dart';
import '../theme/palette.dart';

class SandField extends StatelessWidget {
  const SandField({
    super.key,
    required this.grid,
    required this.pour,
    required this.impact,
    required this.clockMs,
  });

  final SandGrid grid;
  final int pour;
  final double impact;
  final int clockMs;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SandPainter(grid: grid, pour: pour, impact: impact, clockMs: clockMs),
      child: const SizedBox.expand(),
    );
  }
}

class _SandPainter extends CustomPainter {
  _SandPainter({required this.grid, required this.pour, required this.impact, required this.clockMs});

  final SandGrid grid;
  final int pour;
  final double impact;
  final int clockMs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.pit);
    final shadow = Paint()..color = const Color(0x66000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, size.height - 18), width: size.width * 0.72, height: 22),
      shadow,
    );
    final colW = size.width / SandGrid.cols;
    for (var col = 0; col < SandGrid.cols; col++) {
      var y = size.height - 16.0;
      for (var row = SandGrid.rows - 1; row >= 0; row--) {
        final mass = grid.cell(col, row);
        for (var k = 0; k < mass; k++) {
          final n = _hash(col, row, k);
          final wet = mass >= 8;
          final color = wet
              ? Color.lerp(Palette.wet, Palette.beige, (n % 5) / 12)!
              : mass <= 2
              ? Palette.dust
              : Color.lerp(Palette.beige, Palette.dust, (n % 4) / 10)!;
          final radius = 2.6 + (n % 4) * 0.35;
          final squash = impact > 0 && row > 15 ? 1 + impact * 0.35 : 1.0;
          final cx = col * colW + colW / 2 + ((n % 7) - 3) * 0.7;
          y -= radius * 1.15;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, y), width: radius * 2.3 * squash, height: radius * 1.45 / squash),
            Paint()..color = color,
          );
        }
      }
    }
    if (pour > 0) {
      final phase = (clockMs % 800) / 800;
      final paint = Paint()..color = Palette.beige;
      for (var i = 0; i < 16; i++) {
        final t = (i / 16 + phase) % 1;
        final yy = t * (size.height - 24);
        final xx = size.width - 14 - (i % 3) * 5;
        canvas.drawCircle(Offset(xx, yy), 2.1, paint);
      }
    }
    if (impact > 0.05) {
      final dust = Paint()..color = Palette.dust.withValues(alpha: impact * 0.8);
      for (var i = 0; i < 10; i++) {
        final x = size.width * (0.2 + (i % 5) * 0.12);
        final y = size.height * (0.55 - impact * 0.25) - i * 3;
        canvas.drawCircle(Offset(x, y), 2 + impact * 3, dust);
      }
    }
  }

  int _hash(int a, int b, int c) => (a * 73856093 ^ b * 19349663 ^ c * 83492791) & 0x7fffffff;

  @override
  bool shouldRepaint(covariant _SandPainter old) => true;
}
