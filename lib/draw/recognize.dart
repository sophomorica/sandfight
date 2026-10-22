part of 'race.dart';

const _minPoints = 12;
const _minSpan = 48.0;
const _closeFraction = 0.2;
const _circleCv = 0.08;
const _minRadius = 0.05;
const _turnLow = 5.0;
const _turnHigh = 7.8;
const _resampleCount = 64;
const _cornerMin = 0.5;
const _cornerMerge = 4;
const _right = math.pi / 2;
const _rightSlop = 0.45;
const _edgeRatio = 0.72;
const _degenerate = 0.35;

bool strokeMatches(Glyph glyph, Stroke stroke) {
  final norm = _normalize(stroke.points);
  if (norm == null) return false;
  return switch (glyph) {
    Glyph.circle => _isCircle(norm),
    Glyph.square => _isPolygon(norm, 4, square: true),
    Glyph.triangle => _isPolygon(norm, 3, square: false),
  };
}

final class _Norm {
  const _Norm(this.points);

  final List<DrawPoint> points;
}

_Norm? _normalize(List<DrawPoint> raw) {
  if (raw.length < _minPoints) return null;
  var minX = raw.first.x;
  var maxX = minX;
  var minY = raw.first.y;
  var maxY = minY;
  for (final point in raw) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }
  final width = maxX - minX;
  final height = maxY - minY;
  final longer = width > height ? width : height;
  if (longer < _minSpan) return null;
  final scale = 1 / longer;
  return _Norm([
    for (final point in raw)
      DrawPoint((point.x - minX) * scale, (point.y - minY) * scale),
  ]);
}

bool _isCircle(_Norm norm) {
  final points = norm.points;
  if (!_closed(points)) return false;
  final center = _centroid(points);
  var sum = 0.0;
  final radii = <double>[];
  for (final point in points) {
    final radius = _dist(point, center);
    radii.add(radius);
    sum += radius;
  }
  final mean = sum / radii.length;
  if (mean < _minRadius) return false;
  var variance = 0.0;
  for (final radius in radii) {
    final delta = radius - mean;
    variance += delta * delta;
  }
  final cv = math.sqrt(variance / radii.length) / mean;
  if (cv > _circleCv) return false;
  final turn = _loopTurn(points);
  return turn >= _turnLow && turn <= _turnHigh;
}

bool _isPolygon(_Norm norm, int sides, {required bool square}) {
  final points = norm.points;
  if (!_closed(points)) return false;
  final loop = _resample(_closedLoop(points), _resampleCount);
  final corners = _corners(loop);
  if (corners.length != sides) return false;
  final turns = <double>[];
  for (var i = 0; i < corners.length; i++) {
    final previous = loop[corners[(i - 1 + corners.length) % corners.length]];
    final here = loop[corners[i]];
    final next = loop[corners[(i + 1) % corners.length]];
    turns.add(_signedTurn(previous, here, next).abs());
  }
  if (square) {
    for (final turn in turns) {
      if ((turn - _right).abs() > _rightSlop) return false;
    }
    return _oppositeEdges(loop, corners);
  }
  for (final turn in turns) {
    final interior = math.pi - turn;
    if (interior < _degenerate) return false;
  }
  return true;
}

bool _oppositeEdges(List<DrawPoint> loop, List<int> corners) {
  final n = loop.length;
  double span(int from, int to) {
    final steps = (to - from + n) % n;
    return steps.toDouble();
  }

  final edges = [
    span(corners[0], corners[1]),
    span(corners[1], corners[2]),
    span(corners[2], corners[3]),
    span(corners[3], corners[0]),
  ];
  bool near(double a, double b) {
    final high = a > b ? a : b;
    if (high <= 0) return false;
    final low = a < b ? a : b;
    return low / high >= _edgeRatio;
  }

  return near(edges[0], edges[2]) && near(edges[1], edges[3]);
}

List<int> _corners(List<DrawPoint> loop) {
  final n = loop.length;
  if (n < 3) return const [];
  final turn = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    turn[i] = _signedTurn(
      loop[(i - 1 + n) % n],
      loop[i],
      loop[(i + 1) % n],
    ).abs();
  }
  final peaks = <int>[];
  for (var i = 0; i < n; i++) {
    if (turn[i] < _cornerMin) continue;
    if (turn[i] < turn[(i - 1 + n) % n]) continue;
    if (turn[i] < turn[(i + 1) % n]) continue;
    peaks.add(i);
  }
  if (peaks.isEmpty) return const [];
  var start = 0;
  for (var i = 0; i < peaks.length; i++) {
    final next = peaks[(i + 1) % peaks.length];
    if (_circularDistance(peaks[i], next, n) > _cornerMerge) {
      start = (i + 1) % peaks.length;
      break;
    }
  }
  final ordered = <int>[
    for (var i = 0; i < peaks.length; i++) peaks[(start + i) % peaks.length],
  ];
  final groups = <List<int>>[
    [ordered.first],
  ];
  for (var i = 1; i < ordered.length; i++) {
    if (_circularDistance(groups.last.last, ordered[i], n) <= _cornerMerge) {
      groups.last.add(ordered[i]);
    } else {
      groups.add([ordered[i]]);
    }
  }
  return [for (final group in groups) _sharpest(group, turn)];
}

int _sharpest(List<int> group, List<double> turn) {
  var best = group.first;
  for (final index in group) {
    if (turn[index] > turn[best]) best = index;
  }
  return best;
}

int _circularDistance(int a, int b, int n) {
  final delta = (a - b).abs();
  final wrap = n - delta;
  return delta < wrap ? delta : wrap;
}

List<DrawPoint> _resample(List<DrawPoint> points, int count) {
  final lengths = <double>[0];
  for (var i = 1; i < points.length; i++) {
    lengths.add(lengths.last + _dist(points[i - 1], points[i]));
  }
  final total = lengths.last;
  if (total == 0 || count < 2) return points;
  final out = <DrawPoint>[];
  var segment = 1;
  for (var k = 0; k < count; k++) {
    final target = total * k / count;
    while (segment < lengths.length - 1 && lengths[segment] < target) {
      segment += 1;
    }
    final start = lengths[segment - 1];
    final end = lengths[segment];
    final span = end - start;
    final t = span == 0 ? 0.0 : (target - start) / span;
    final a = points[segment - 1];
    final b = points[segment];
    out.add(DrawPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
  }
  return out;
}

List<DrawPoint> _closedLoop(List<DrawPoint> points) {
  if (_dist(points.first, points.last) < 1e-6) return points;
  return [...points, points.first];
}

bool _closed(List<DrawPoint> points) {
  final perimeter = _perimeter(points);
  if (perimeter <= 0) return false;
  return _dist(points.first, points.last) / perimeter <= _closeFraction;
}

double _loopTurn(List<DrawPoint> points) {
  final n = points.length;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += _signedTurn(
      points[(i - 1 + n) % n],
      points[i],
      points[(i + 1) % n],
    ).abs();
  }
  return sum;
}

double _signedTurn(DrawPoint a, DrawPoint b, DrawPoint c) {
  final ax = b.x - a.x;
  final ay = b.y - a.y;
  final bx = c.x - b.x;
  final by = c.y - b.y;
  return math.atan2(ax * by - ay * bx, ax * bx + ay * by);
}

DrawPoint _centroid(List<DrawPoint> points) {
  var length = 0.0;
  var x = 0.0;
  var y = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final span = _dist(a, b);
    if (span == 0) continue;
    length += span;
    x += (a.x + b.x) * 0.5 * span;
    y += (a.y + b.y) * 0.5 * span;
  }
  if (length == 0) return points.first;
  return DrawPoint(x / length, y / length);
}

double _perimeter(List<DrawPoint> points) {
  var sum = 0.0;
  for (var i = 1; i < points.length; i++) {
    sum += _dist(points[i - 1], points[i]);
  }
  return sum;
}

double _dist(DrawPoint a, DrawPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}
