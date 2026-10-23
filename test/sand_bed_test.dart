import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/render/aim_overlay.dart';
import 'package:sandfight/render/sand_bed.dart';
import 'package:sandfight/render/sand_look.dart';

void main() {
  test('hash matches the zen prototype', () {
    expect(sandHashUint(0, 0), 0);
    expect(sandHashUint(3, 5), 407618539);
    expect(sandHashUint(11, 91), 600080964);
    expect(sandHashUint(-4, 8), 545294784);
    expect(sandHashUint(100, 250), 3825238016);
  });

  test('0 is up, +30 is clockwise, -30 is the other way', () {
    expect(screenAngleDeg(0, -1), closeTo(0, 0.001));
    expect(screenAngleDeg(0.5, -math.sqrt(3) / 2), closeTo(30, 0.001));
    expect(screenAngleDeg(-0.5, -math.sqrt(3) / 2), closeTo(-30, 0.001));
    expect(formatAngle(30), '+30°');
    expect(formatAngle(-30), '-30°');
    expect(formatAngle(0), '0°');
  });

  test('a bent stroke carves the corner and leaves the chord alone', () {
    final bed = SandBed.fit(180, 280, simScale: 1);
    const corner = SandSample(90, 140, 80);
    play(bed, const [
      SandSample(40, 200, 0),
      corner,
      SandSample(40, 80, 160),
    ]);
    expect(bed.samples.any((sample) => sample.x == 90 && sample.y == 140), isTrue);
    expect(bed.at(90, 140), lessThan(bed.fresh[140 * bed.cols + 90] - 0.4));
    final chord = 140 * bed.cols + 40;
    expect(bed.at(40, 140), closeTo(bed.fresh[chord], 0.001));
  });

  test('upward strokes at 30, 0, and -30 follow the finger', () {
    for (final angle in [30.0, 0.0, -30.0]) {
      final bed = SandBed.fit(220, 320, simScale: 1);
      const start = (x: 70.0, y: 260.0);
      final samples = line(start.x, start.y, angle, 180, 400, 28);
      play(bed, samples);
      final carved = _carved(bed, 0.45);
      expect(carved, isNotEmpty, reason: 'angle $angle');
      final rad = angle * math.pi / 180;
      final ux = math.sin(rad);
      final uy = -math.cos(rad);
      for (final cell in carved) {
        final distance = _distanceToSegment(cell.x.toDouble(), cell.y.toDouble(), start.x, start.y, start.x + ux * 180, start.y + uy * 180);
        expect(distance, lessThan(SandLook.fingerRadius * 2.6), reason: 'angle $angle cell ${cell.x},${cell.y}');
      }
      final xs = carved.map((cell) => cell.x);
      if (angle > 10) {
        expect(xs.reduce(math.max), greaterThan(start.x + 40));
      }
      if (angle < -10) {
        expect(xs.reduce(math.min), lessThan(start.x - 40));
      }
      if (angle == 0) {
        expect(xs.reduce(math.max) - xs.reduce(math.min), lessThan(20));
        expect(bed.at(200, 160), closeTo(bed.fresh[160 * bed.cols + 200], 0.001));
      }
      final readout = summaryAim(bed.samples, peak: bed.peak, length: bed.length);
      expect(readout.angleDeg, closeTo(angle, 0.05));
    }
  });

  test('a fast flick is shallower than the same path drawn slowly', () {
    final slow = _middleDepth(2000);
    final fast = _middleDepth(70);
    expect(slow, lessThan(fast - 0.3));
  });

  test('reset puts the fresh garden back', () {
    final bed = SandBed.fit(120, 180, simScale: 1);
    play(bed, line(60, 140, 0, 80, 400, 16));
    final i = 100 * bed.cols + 60;
    expect(bed.at(60, 100), lessThan(bed.fresh[i] - 0.2));
    bed.resetGarden();
    expect(bed.at(60, 100), closeTo(bed.fresh[i], 1e-6));
    expect(bed.samples, isEmpty);
  });

  test('smooth raises a trench', () {
    final bed = SandBed.fit(80, 160, simScale: 1);
    play(bed, line(40, 130, 0, 80, 600, 20));
    final cells = _carved(bed, 0.45);
    expect(cells, isNotEmpty);
    final before = [for (final cell in cells) bed.at(cell.x, cell.y)];
    bed.smoothGarden();
    var rose = 0.0;
    for (var i = 0; i < cells.length; i++) {
      rose += bed.at(cells[i].x, cells[i].y) - before[i];
    }
    expect(rose / cells.length, greaterThan(0.05));
  });

  test('a rake cuts wider than a finger', () {
    final finger = SandBed.fit(180, 80, simScale: 1);
    final rake = SandBed.fit(180, 80, simScale: 1)..rake = true;
    final stroke = line(20, 40, 90, 140, 500, 24);
    play(finger, stroke);
    play(rake, stroke);
    final fingerSpan = _spanY(_carved(finger, 0.4));
    final rakeSpan = _spanY(_carved(rake, 0.4));
    expect(rakeSpan, greaterThan(fingerSpan + 16));
  });

  test('slump keeps the sand it moves', () {
    final bed = SandBed.fit(48, 48, simScale: 1);
    final before = bed.height.fold<double>(0, (sum, value) => sum + value);
    final neighbor = bed.at(21, 20);
    bed.lift(20, 20, 4);
    bed.slump();
    final after = bed.height.fold<double>(0, (sum, value) => sum + value);
    expect(after, closeTo(before + 4, 1e-3));
    expect(bed.at(20, 20), lessThan(bed.fresh[20 * bed.cols + 20] + 4));
    expect(bed.at(21, 20), greaterThan(neighbor));
  });

  test('carve time on a phone-sized bed', () {
    const width = 390.0;
    const height = 700.0;
    final samples = line(width / 2, height * 0.86, 0, height * 0.62, 320, 48);
    final warmup = SandBed.fit(width, height);
    play(warmup, samples);
    warmup.encodeHeight();

    final bed = SandBed.fit(width, height);
    final shown = Uint8List.fromList(bed.encodeHeight());
    expect(shown.length, bed.cols * bed.rows * 4);
    final watch = Stopwatch()..start();
    bed.down(1, samples.first.x, samples.first.y, samples.first.tMs);
    var worstUs = 0;
    for (var i = 1; i < samples.length; i++) {
      final started = watch.elapsedMicroseconds;
      bed.move(1, samples[i].x, samples[i].y, samples[i].tMs);
      final spent = watch.elapsedMicroseconds - started;
      if (spent > worstUs) worstUs = spent;
    }
    final carveUs = watch.elapsedMicroseconds;
    final slumpStarted = watch.elapsedMicroseconds;
    bed.up(1, samples.last.x, samples.last.y, samples.last.tMs);
    bed.slump();
    final slumpUs = watch.elapsedMicroseconds - slumpStarted;
    final encodeStarted = watch.elapsedMicroseconds;
    final bytes = bed.encodeHeight();
    final encodeUs = watch.elapsedMicroseconds - encodeStarted;
    // ignore: avoid_print
    print(
      'BENCH cells ${bed.cols}x${bed.rows} scale ${bed.cellsPerPt.toStringAsFixed(3)} '
      'carve ${(carveUs / 1000).toStringAsFixed(2)} ms '
      'worst ${(worstUs / 1000).toStringAsFixed(2)} ms '
      'slump ${(slumpUs / 1000).toStringAsFixed(2)} ms '
      'encode ${(encodeUs / 1000).toStringAsFixed(2)} ms '
      'bytes ${bytes.length}',
    );
    expect(bed.cols * bed.rows, lessThanOrEqualTo(SandLook.maxCells));
    expect(worstUs, lessThan(16000));
    expect(encodeUs, lessThan(4000));
    expect(_packedMatches(bed, bytes), isTrue);
    expect(_untouchedBytes(bed, bytes, shown), isTrue);
  });

  test('a later stroke repacks the cells it moved', () {
    final bed = SandBed.fit(120, 180, simScale: 1);
    bed.encodeHeight();
    play(bed, line(60, 150, 0, 80, 400, 16));
    expect(_packedMatches(bed, bed.encodeHeight()), isTrue);
    play(bed, line(30, 150, 20, 80, 400, 16));
    expect(_packedMatches(bed, bed.encodeHeight()), isTrue);
    bed.smoothGarden();
    expect(_packedMatches(bed, bed.encodeHeight()), isTrue);
    bed.resetGarden();
    expect(_packedMatches(bed, bed.encodeHeight()), isTrue);
  });
}

bool _packedMatches(SandBed bed, Uint8List bytes) {
  const span = SandLook.heightMax - SandLook.heightMin;
  for (var i = 0; i < bed.cols * bed.rows; i++) {
    final o = i * 4;
    if (bytes[o + 2] != 0 || bytes[o + 3] != 255) return false;
    final t = (bytes[o] + bytes[o + 1] / 255.0) / 255.0;
    final height = t * span + SandLook.heightMin;
    if ((height - bed.height[i]).abs() > 0.002) return false;
  }
  return true;
}

bool _untouchedBytes(SandBed bed, Uint8List bytes, Uint8List shown) {
  var held = 0;
  for (var i = 0; i < bed.height.length; i++) {
    if (bed.height[i] != bed.fresh[i]) continue;
    final o = i * 4;
    if (bytes[o] != shown[o] || bytes[o + 1] != shown[o + 1]) return false;
    held++;
  }
  return held > bed.height.length ~/ 2;
}

void play(SandBed bed, List<SandSample> samples) {
  bed.down(1, samples.first.x, samples.first.y, samples.first.tMs);
  for (var i = 1; i < samples.length - 1; i++) {
    bed.move(1, samples[i].x, samples[i].y, samples[i].tMs);
  }
  bed.up(1, samples.last.x, samples.last.y, samples.last.tMs);
  bed.slump();
}

List<SandSample> line(double x, double y, double angleDeg, double length, double durationMs, int count) {
  final rad = angleDeg * math.pi / 180;
  final ux = math.sin(rad);
  final uy = -math.cos(rad);
  return [
    for (var i = 0; i < count; i++)
      SandSample(
        x + ux * length * i / (count - 1),
        y + uy * length * i / (count - 1),
        durationMs * i / (count - 1),
      ),
  ];
}

double _middleDepth(double durationMs) {
  final bed = SandBed.fit(120, 240, simScale: 1);
  play(bed, line(60, 200, 0, 140, durationMs, 24));
  var deepest = 1.0;
  for (var y = 110; y <= 150; y++) {
    for (var x = 52; x <= 68; x++) {
      final value = bed.at(x, y);
      if (value < deepest) deepest = value;
    }
  }
  return deepest;
}

List<({int x, int y})> _carved(SandBed bed, double belowFresh) {
  final found = <({int x, int y})>[];
  for (var y = 1; y < bed.rows - 1; y++) {
    for (var x = 1; x < bed.cols - 1; x++) {
      if (bed.at(x, y) < bed.fresh[y * bed.cols + x] - belowFresh) {
        found.add((x: x, y: y));
      }
    }
  }
  return found;
}

int _spanY(List<({int x, int y})> cells) {
  final ys = cells.map((cell) => cell.y);
  return ys.reduce(math.max) - ys.reduce(math.min);
}

double _distanceToSegment(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  final l2 = dx * dx + dy * dy;
  final t = ((px - ax) * dx + (py - ay) * dy) / l2;
  final tc = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  final qx = ax + tc * dx - px;
  final qy = ay + tc * dy - py;
  return math.sqrt(qx * qx + qy * qy);
}
