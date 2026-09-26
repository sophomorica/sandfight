import 'dart:math' as math;
import 'dart:typed_data';

import 'sand_look.dart';

class SandSample {
  const SandSample(this.x, this.y, this.tMs);

  final double x;
  final double y;
  final double tMs;
}

class SandBed {
  SandBed._({
    required this.cols,
    required this.rows,
    required this.cellsPerPt,
    required this.widthPt,
    required this.heightPt,
    required this.seed,
  }) : height = Float32List(cols * rows),
       fresh = Float32List(cols * rows),
       _noiseF = Float32List(cols * rows),
       _noiseM = Float32List(cols * rows),
       _mark = Int32List(cols * rows) {
    _fillFresh();
  }

  factory SandBed.fit(
    double widthPt,
    double heightPt, {
    int seed = 11,
    double simScale = SandLook.simScale,
    int maxCells = SandLook.maxCells,
  }) {
    var scale = simScale;
    final area = widthPt * heightPt;
    if (area > 0 && area * scale * scale > maxCells) {
      scale = math.sqrt(maxCells / area);
    }
    final cols = math.max(8, (widthPt * scale).round());
    final rows = math.max(8, (heightPt * scale).round());
    return SandBed._(
      cols: cols,
      rows: rows,
      cellsPerPt: cols / widthPt,
      widthPt: widthPt,
      heightPt: heightPt,
      seed: seed,
    );
  }

  final int cols;
  final int rows;
  final double cellsPerPt;
  final double widthPt;
  final double heightPt;
  final int seed;
  final Float32List height;
  final Float32List fresh;

  final Float32List _noiseF;
  final Float32List _noiseM;
  final Int32List _mark;

  int generation = 0;
  _Dirty? _dirty;
  int _nextSid = 1;
  final _strokes = <int, _Stroke>{};
  List<SandSample> _shown = const [];

  int? _activePointer;

  bool get stroking => _activePointer != null;

  bool get dirty => _dirty != null;

  List<SandSample> get samples => _shown;

  double get length => _active?.len ?? _closedLen;

  double get peak => _active?.peak ?? _closedPeak;

  double _closedLen = 0;
  double _closedPeak = 0;

  _Stroke? get _active {
    final id = _activePointer;
    if (id == null) return null;
    return _strokes[id];
  }

  void down(int pointer, double x, double y, double tMs) {
    final previous = _activePointer;
    if (previous != null && previous != pointer) {
      up(previous, _strokes[previous]!.raw.last.x, _strokes[previous]!.raw.last.y, _strokes[previous]!.raw.last.tMs);
    }
    final stroke = _Stroke(
      pointer: pointer,
      sid: _nextSid++,
      seed: (seed * 17 + pointer) % 997 + 0.5,
      random: math.Random(seed * 10007 + _nextSid * 13 + pointer),
      t0: tMs,
    );
    _strokes[pointer] = stroke;
    _activePointer = pointer;
    _push(stroke, x, y, tMs);
    _shown = stroke.raw;
  }

  void move(int pointer, double x, double y, double tMs) {
    final stroke = _strokes[pointer];
    if (stroke == null) return;
    _push(stroke, x, y, tMs);
  }

  void up(int pointer, double x, double y, double tMs) {
    final stroke = _strokes.remove(pointer);
    if (stroke == null) return;
    if (_activePointer == pointer) _activePointer = _strokes.keys.isEmpty ? null : _strokes.keys.first;
    _push(stroke, x, y, tMs);
    _finish(stroke);
    _shown = List<SandSample>.of(stroke.raw);
    _closedLen = stroke.len;
    _closedPeak = stroke.peak;
  }

  void lift(int x, int y, double amount) {
    height[y * cols + x] += amount;
    _markDirty(x, y, x, y);
  }

  void slump() {
    final box = _dirty;
    if (box == null) return;
    _relax(box.x0, box.y0, box.x1, box.y1);
    _dirty = null;
    generation += 1;
  }

  Uint8List encodeHeight() {
    final n = cols * rows;
    final out = Uint8List(n * 4);
    const span = SandLook.heightMax - SandLook.heightMin;
    for (var i = 0; i < n; i++) {
      final t = ((height[i] - SandLook.heightMin) / span).clamp(0.0, 1.0);
      final scaled = t * 255.0;
      final r = scaled.floor().clamp(0, 255);
      final g = ((scaled - r) * 255.0).round().clamp(0, 255);
      final o = i * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = 0;
      out[o + 3] = 255;
    }
    return out;
  }

  double at(int x, int y) => height[y * cols + x];

  void _fillFresh() {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final i = y * cols + x;
        final lo = sandNoise2(x / 110 + seed, y / 110) * 0.6 + sandNoise2(x / 45, y / 45 + seed) * 0.4;
        final hi = sandNoise2(x / 5 + 7.3, y / 5 + seed) - 0.5;
        final base = (lo - 0.5) * 0.7 + hi * 0.1;
        fresh[i] = base;
        height[i] = base;
        _noiseF[i] = sandHash01(x + seed, y) * 2 - 1;
        _noiseM[i] = (sandNoise2(x / 2.6 + seed, y / 2.6) * 0.7 + sandNoise2(x / 7 + 3.1, y / 7 + seed) * 0.3) * 2 - 1;
      }
    }
  }

  void _push(_Stroke stroke, double x, double y, double tMs) {
    if (tMs < stroke.lastT) return;
    final prev = stroke.raw.isEmpty ? null : stroke.raw.last;
    if (prev != null && tMs == stroke.lastT && prev.x == x && prev.y == y) return;
    stroke.lastT = tMs;
    stroke.raw.add(SandSample(x, y, tMs));
    if (stroke.raw.length > 600) stroke.raw.removeAt(0);
    if (prev == null) {
      stroke.path.add(SandSample(x, y, tMs));
      return;
    }
    final d = math.sqrt((x - prev.x) * (x - prev.x) + (y - prev.y) * (y - prev.y));
    if (d < 0.25) return;
    stroke.len += d;
    stroke.speed = _windowSpeed(stroke.raw, 40);
    if (stroke.raw.length > 2) {
      final burst = _windowSpeed(stroke.raw, 60);
      if (burst > stroke.peak) stroke.peak = burst;
    }
    final from = stroke.path.last;
    stroke.path.add(SandSample(x, y, tMs));
    if (stroke.path.length > 400) stroke.path.removeAt(0);
    _carveFinger(stroke, from.x, from.y, x, y);
  }

  void _carveFinger(_Stroke stroke, double ax, double ay, double bx, double by) {
    final c = cellsPerPt;
    final s = _speed01(stroke.speed);
    final r = SandLook.fingerRadius * c * (1 + SandLook.widthGain * s);
    final depth = SandLook.fingerDepth * SandLook.fingerRadius * c * (1 - SandLook.depthLoss * s);
    final head = _heading(stroke.path, 6);
    _carveSegment(
      ax * c,
      ay * c,
      bx * c,
      by * c,
      r,
      depth,
      SandLook.fingerProfile,
      stroke.seed,
      stroke.sid,
      SandLook.aheadBase + SandLook.aheadGain * s,
      head?.dx,
      head?.dy,
      stroke,
      false,
    );
    stroke.lastR = r;
    stroke.lastDepth = depth;
  }

  void _finish(_Stroke stroke) {
    final path = stroke.path;
    final c = cellsPerPt;
    if (path.length == 1) {
      _carveFinger(stroke, path[0].x - 0.3, path[0].y, path[0].x + 0.3, path[0].y);
      return;
    }
    if (path.length >= 2 && stroke.lastR > 0) {
      final dir = _heading(path, 8);
      if (dir != null) {
        final end = path.last;
        final s = _speed01(stroke.speed);
        final bx = end.x * c;
        final by = end.y * c;
        _carveSegment(
          bx - dir.dx * 0.5,
          by - dir.dy * 0.5,
          bx,
          by,
          stroke.lastR,
          stroke.lastDepth,
          SandLook.fingerProfile,
          stroke.seed,
          stroke.sid,
          SandLook.aheadBase + SandLook.aheadGain * s,
          dir.dx,
          dir.dy,
          stroke,
          true,
        );
        final flick = _speed01(_windowSpeed(stroke.raw, 60));
        if (flick >= 0.25) _spray(stroke, dir.dx, dir.dy, flick);
      }
    }
  }

  void _spray(_Stroke stroke, double dx, double dy, double s) {
    final c = cellsPerPt;
    final end = stroke.path.last;
    final r = SandLook.fingerRadius * c;
    final n = (10 + 30 * s * SandLook.spray).round();
    final random = stroke.random;
    for (var k = 0; k < n; k++) {
      final dist = r * (1.3 + random.nextDouble() * (1.5 + 4 * s));
      final spread = (random.nextDouble() - 0.5) * (0.9 + 0.5 * s);
      final cs = math.cos(spread);
      final sn = math.sin(spread);
      final sx = dx * cs - dy * sn;
      final sy = dx * sn + dy * cs;
      final amp = (0.6 + random.nextDouble() * 0.8) * (1 - dist / (r * 7.5)) * SandLook.spray;
      _bump(end.x * c + sx * dist, end.y * c + sy * dist, 1.1 + random.nextDouble() * 1.4, amp);
    }
  }

  void _bump(double cx, double cy, double rad, double amp) {
    final x0 = math.max(1, (cx - rad * 2).floor());
    final x1 = math.min(cols - 2, (cx + rad * 2).ceil());
    final y0 = math.max(1, (cy - rad * 2).floor());
    final y1 = math.min(rows - 2, (cy + rad * 2).ceil());
    final k = 1 / (rad * rad);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final ddx = x - cx;
        final ddy = y - cy;
        height[y * cols + x] += amp * math.exp(-(ddx * ddx + ddy * ddy) * k);
      }
    }
    _markDirty(x0, y0, x1, y1);
  }

  double _carveSegment(
    double ax,
    double ay,
    double bx,
    double by,
    double r,
    double depth,
    double profilePow,
    double seed,
    int sid,
    double ahead,
    double? headingX,
    double? headingY,
    _Stroke stroke,
    bool flush,
  ) {
    final outer = r * SandLook.ridgeOuter;
    final inner = r * SandLook.ridgeInner;
    final x0 = math.max(1, (math.min(ax, bx) - outer - 1).floor());
    final x1 = math.min(cols - 2, (math.max(ax, bx) + outer + 1).ceil());
    final y0 = math.max(1, (math.min(ay, by) - outer - 1).floor());
    final y1 = math.min(rows - 2, (math.max(ay, by) + outer + 1).ceil());
    if (x1 <= x0 || y1 <= y0) return 0;
    final dx = bx - ax;
    final dy = by - ay;
    final l2 = math.max(dx * dx + dy * dy, 1e-6);
    final len = math.sqrt(l2);
    final fx = headingX ?? dx / len;
    final fy = headingY ?? dy / len;
    final flen = math.max(0.0, dx * fx + dy * fy);
    final streaks = SandLook.streaks;
    final crumble = SandLook.ridgeCrumble;
    final wobble = SandLook.edgeWobble;
    var removed = 0.0;
    final idx = <int>[];
    final weights = <double>[];
    var sumW = 0.0;
    for (var y = y0; y <= y1; y++) {
      final py = y - ay;
      for (var x = x0; x <= x1; x++) {
        final px = x - ax;
        final t = (px * dx + py * dy) / l2;
        final tc = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
        final qx = px - tc * dx;
        final qy = py - tc * dy;
        final dist = math.sqrt(qx * qx + qy * qy);
        final i = y * cols + x;
        final rr = r * (1 + wobble * _noiseM[i]);
        if (dist < rr) {
          final u = dist / rr;
          final lat = (px * dy - py * dx) / (len * r);
          final prof = math.pow(1 - u * u, profilePow).toDouble();
          final st = 1 + streaks * (sandNoise1(lat * 5.5 + seed) * 2 - 1) + 0.06 * _noiseF[i];
          final target = -depth * prof * st;
          final cur = height[i];
          if (cur > target) {
            removed += cur - target;
            height[i] = target;
          }
          _mark[i] = sid;
        } else if (dist < outer && _mark[i] != sid) {
          final along = px * fx + py * fy;
          final latD = (px * fy - py * fx).abs();
          var ws = latD < outer ? _clamp(along + 0.5, 0, 1) * _clamp(flen - along + 0.5, 0, 1) : 0.0;
          if (ahead > 0 && along > flen - 0.5 && latD < r * 0.9) {
            ws += ahead * _clamp(along - flen + 0.5, 0, 1);
          }
          if (ws <= 0) continue;
          var v = (math.max(latD, along > flen ? dist : 0.0) - inner) / (outer - inner);
          v = math.pow(_clamp(v, 0, 1), 0.65).toDouble();
          final w = ws * math.pow(math.sin(math.pi * v), 1.5).toDouble() * (1 + crumble * (0.5 * _noiseF[i] + 0.5 * _noiseM[i]));
          if (w > 0) {
            idx.add(i);
            weights.add(w);
            sumW += w;
          }
        }
      }
    }
    var amount = removed * SandLook.ridgeRatio;
    stroke.pool += amount;
    amount = flush ? stroke.pool : stroke.pool * _clamp(flen / (r * 1.5), 0, 1);
    if (amount > 0 && sumW > 0) {
      stroke.pool -= amount;
      final k = amount / sumW;
      final bw = x1 - x0 + 5;
      final bh = y1 - y0 + 5;
      final bn = bw * bh;
      final depA = Float32List(bn);
      final depB = Float32List(bn);
      for (var j = 0; j < idx.length; j++) {
        final i = idx[j];
        final xx = i % cols - x0 + 2;
        final yy = i ~/ cols - y0 + 2;
        depA[yy * bw + xx] += weights[j] * k;
      }
      for (var yy = 0; yy < bh; yy++) {
        for (var xx = 2; xx < bw - 2; xx++) {
          final q = yy * bw + xx;
          depB[q] = (depA[q - 2] + 4 * depA[q - 1] + 6 * depA[q] + 4 * depA[q + 1] + depA[q + 2]) * 0.0625;
        }
      }
      for (var yy = 2; yy < bh - 2; yy++) {
        final gy = y0 - 2 + yy;
        if (gy < 0 || gy >= rows) continue;
        for (var xx = 0; xx < bw; xx++) {
          final gx = x0 - 2 + xx;
          if (gx < 0 || gx >= cols) continue;
          final q = yy * bw + xx;
          height[gy * cols + gx] += (depB[q - 2 * bw] + 4 * depB[q - bw] + 6 * depB[q] + 4 * depB[q + bw] + depB[q + 2 * bw]) * 0.0625;
        }
      }
    }
    _markDirty(x0 - 2, y0 - 2, x1 + 2, y1 + 2);
    return removed;
  }

  void _relax(int x0, int y0, int x1, int y1) {
    const t = SandLook.talus;
    final left = math.max(1, x0 - 2);
    final top = math.max(1, y0 - 2);
    final right = math.min(cols - 2, x1 + 2);
    final bottom = math.min(rows - 2, y1 + 2);
    for (var iter = 0; iter < SandLook.relaxIters; iter++) {
      for (var y = top; y <= bottom; y++) {
        var i = y * cols + left;
        for (var x = left; x <= right; x++, i++) {
          final hi = height[i];
          var d = hi - height[i + 1];
          if (d > t) {
            final m = (d - t) * 0.25;
            height[i] -= m;
            height[i + 1] += m;
          } else if (d < -t) {
            final m = (-d - t) * 0.25;
            height[i] += m;
            height[i + 1] -= m;
          }
          d = height[i] - height[i + cols];
          if (d > t) {
            final m = (d - t) * 0.25;
            height[i] -= m;
            height[i + cols] += m;
          } else if (d < -t) {
            final m = (-d - t) * 0.25;
            height[i] += m;
            height[i + cols] -= m;
          }
        }
      }
    }
  }

  void _markDirty(int x0, int y0, int x1, int y1) {
    final left = math.max(0, x0);
    final top = math.max(0, y0);
    final right = math.min(cols - 1, x1);
    final bottom = math.min(rows - 1, y1);
    final box = _dirty;
    if (box == null) {
      _dirty = _Dirty(left, top, right, bottom);
      return;
    }
    if (left < box.x0) box.x0 = left;
    if (top < box.y0) box.y0 = top;
    if (right > box.x1) box.x1 = right;
    if (bottom > box.y1) box.y1 = bottom;
  }
}

class _Stroke {
  _Stroke({required this.pointer, required this.sid, required this.seed, required this.random, required this.t0});

  final int pointer;
  final int sid;
  final double seed;
  final math.Random random;
  final double t0;
  final raw = <SandSample>[];
  final path = <SandSample>[];
  double lastT = -1;
  double len = 0;
  double speed = 0;
  double peak = 0;
  double pool = 0;
  double lastR = 0;
  double lastDepth = 0;
}

class _Heading {
  const _Heading(this.dx, this.dy);
  final double dx;
  final double dy;
}

class _Dirty {
  _Dirty(this.x0, this.y0, this.x1, this.y1);
  int x0;
  int y0;
  int x1;
  int y1;
}

_Heading? _heading(List<SandSample> path, double lead) {
  if (path.length < 2) return null;
  final b = path.last;
  var j = path.length - 2;
  while (j > 0) {
    final p = path[j];
    if (math.sqrt((b.x - p.x) * (b.x - p.x) + (b.y - p.y) * (b.y - p.y)) >= lead) break;
    j--;
  }
  final a = path[math.max(0, j)];
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-6) return null;
  return _Heading(dx / len, dy / len);
}

double _windowSpeed(List<SandSample> raw, double windowMs) {
  final n = raw.length;
  if (n < 2) return 0;
  final last = raw[n - 1];
  var j = n - 2;
  while (j > 0 && last.tMs - raw[j].tMs < windowMs) {
    j--;
  }
  final dt = last.tMs - raw[j].tMs;
  if (dt <= 0) return 0;
  var d = 0.0;
  for (var k = j + 1; k < n; k++) {
    final dx = raw[k].x - raw[k - 1].x;
    final dy = raw[k].y - raw[k - 1].y;
    d += math.sqrt(dx * dx + dy * dy);
  }
  return d / dt * 1000;
}

double _speed01(double speed) => _clamp((speed - SandLook.speedSlow) / (SandLook.speedFast - SandLook.speedSlow), 0, 1);

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
