import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sand_bed.dart';
import 'sand_look.dart';

class AimReadout {
  const AimReadout({
    required this.headline,
    required this.detail,
    required this.angleDeg,
    required this.speed,
    required this.samples,
  });

  final String headline;
  final String detail;
  final double? angleDeg;
  final double speed;
  final List<SandSample> samples;

  static const idle = AimReadout(headline: 'AIM ON', detail: 'drag to measure', angleDeg: null, speed: 0, samples: []);
}

AimReadout liveAim(List<SandSample> samples) {
  if (samples.length < 2) return AimReadout.idle;
  final from = _window(samples, 80);
  final to = samples.last;
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final dist = math.sqrt(dx * dx + dy * dy);
  final dt = to.tMs - from.tMs;
  final angle = dist > 1 ? screenAngleDeg(dx, dy) : null;
  final speed = dt > 0 && dist > 1 ? dist / dt * 1000 : 0.0;
  var length = 0.0;
  for (var i = 1; i < samples.length; i++) {
    final sx = samples[i].x - samples[i - 1].x;
    final sy = samples[i].y - samples[i - 1].y;
    length += math.sqrt(sx * sx + sy * sy);
  }
  return AimReadout(
    headline: angle == null ? '—' : formatAngle(angle),
    detail: '${speed.round()} pt/s   ${length.round()} pt   ${samples.length} samples',
    angleDeg: angle,
    speed: speed,
    samples: samples,
  );
}

AimReadout summaryAim(List<SandSample> samples, {required double peak, required double length}) {
  if (samples.length < 2) return AimReadout.idle;
  var sx = 0.0;
  var sy = 0.0;
  for (var i = 1; i < samples.length; i++) {
    sx += samples[i].x - samples[i - 1].x;
    sy += samples[i].y - samples[i - 1].y;
  }
  final angle = math.sqrt(sx * sx + sy * sy) > 0.5 ? screenAngleDeg(sx, sy) : null;
  final ms = samples.last.tMs - samples.first.tMs;
  return AimReadout(
    headline: 'avg ${angle == null ? '—' : formatAngle(angle)}',
    detail: 'LAST STROKE   peak ${peak.round()} pt/s   ${length.round()} pt   ${ms.round()} ms',
    angleDeg: angle,
    speed: peak,
    samples: samples,
  );
}

String formatAngle(double degrees) {
  final rounded = degrees.round();
  if (rounded > 0) return '+$rounded°';
  if (rounded < 0) return '$rounded°';
  return '0°';
}

class AimOverlay extends StatelessWidget {
  const AimOverlay({super.key, required this.readout, required this.fade});

  final AimReadout readout;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _AimPainter(readout: readout, fade: fade),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AimPainter extends CustomPainter {
  _AimPainter({required this.readout, required this.fade});

  final AimReadout readout;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = readout.samples;
    if (samples.isEmpty || fade <= 0) return;
    final paint = Paint()
      ..color = const Color(0x59FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = ui.Path()..moveTo(samples.first.x, samples.first.y);
    for (final sample in samples) {
      path.lineTo(sample.x, sample.y);
    }
    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(255, 255, 255, fade));
    canvas.drawPath(path, paint..color = const Color(0x59201408));
    final dot = Paint()..color = const Color(0xFFFFFFFF);
    final ring = Paint()
      ..color = const Color(0xCC140E08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final sample in samples) {
      canvas.drawCircle(Offset(sample.x, sample.y), 1.8, dot);
      canvas.drawCircle(Offset(sample.x, sample.y), 1.8, ring);
    }
    canvas.drawCircle(
      Offset(samples.first.x, samples.first.y),
      4,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final angle = readout.angleDeg;
    if (angle != null && samples.length > 1) {
      final rad = angle * math.pi / 180;
      final ux = math.sin(rad);
      final uy = -math.cos(rad);
      final to = samples.last;
      final from = _window(samples, 80);
      final length = (40 + readout.speed * 0.05).clamp(48.0, 170.0);
      final tip = Offset(to.x + ux * length, to.y + uy * length);
      final tail = Offset(from.x, from.y);
      _arrow(canvas, tail, tip, const Color(0x8C140E08), 5);
      _arrow(canvas, tail, tip, const Color(0xFFFFFFFF), 2.2);
      _label(canvas, formatAngle(angle), tip, Offset(ux, uy), size);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AimPainter oldDelegate) {
    if (oldDelegate.fade != fade || oldDelegate.readout.headline != readout.headline) return true;
    if (oldDelegate.readout.samples.length != readout.samples.length) return true;
    if (readout.samples.isEmpty) return false;
    return !identical(oldDelegate.readout.samples.last, readout.samples.last);
  }
}

SandSample _window(List<SandSample> samples, double windowMs) {
  final last = samples.last;
  var j = samples.length - 1;
  while (j > 0 && last.tMs - samples[j - 1].tMs <= windowMs) {
    j--;
  }
  return samples[math.min(j, samples.length - 2)];
}

void _arrow(Canvas canvas, Offset tail, Offset tip, Color color, double width) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas.drawLine(tail, tip, paint);
  final delta = tip - tail;
  final len = delta.distance;
  if (len < 1) return;
  final ux = delta.dx / len;
  final uy = delta.dy / len;
  final s = 11 + (width > 3 ? 2 : 0);
  final head = Path()
    ..moveTo(tip.dx + ux * 3, tip.dy + uy * 3)
    ..lineTo(tip.dx - ux * s - uy * s * 0.6, tip.dy - uy * s + ux * s * 0.6)
    ..lineTo(tip.dx - ux * s + uy * s * 0.6, tip.dy - uy * s - ux * s * 0.6)
    ..close();
  canvas.drawPath(head, Paint()..color = color);
}

void _label(Canvas canvas, String text, Offset tip, Offset dir, Size size) {
  final lx = (tip.dx + dir.dx * 18).clamp(24.0, size.width - 24);
  final ly = (tip.dy + dir.dy * 18).clamp(28.0, size.height - 72);
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 13))
    ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF), fontSize: 13, fontWeight: FontWeight.w600))
    ..addText(text);
  final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 80));
  final tw = paragraph.maxIntrinsicWidth + 12;
  final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(lx, ly), width: tw, height: 20), const Radius.circular(10));
  canvas.drawRRect(rect, Paint()..color = const Color(0xB8140E08));
  canvas.drawParagraph(paragraph, Offset(lx - 40, ly - 8));
}
