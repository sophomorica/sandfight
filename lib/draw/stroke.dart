final class DrawPoint {
  const DrawPoint(this.x, this.y);

  final double x;
  final double y;
}

/// One pointer-down to pointer-up, in bed points. No timestamps.
final class Stroke {
  const Stroke(this.points);

  final List<DrawPoint> points;
}
