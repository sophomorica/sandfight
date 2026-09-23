import 'dart:math' as math;

enum Seat { a, b }

Seat otherSeat(Seat seat) => seat == Seat.a ? Seat.b : Seat.a;

class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  double get length => math.sqrt(x * x + y * y);

  Vec2 unit() {
    final len = length;
    if (len < 1e-9) return const Vec2(0, 1);
    return Vec2(x / len, y / len);
  }

  double dot(Vec2 other) => x * other.x + y * other.y;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);

  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
}

class Pose {
  const Pose(this.xy, this.hdg);

  final Vec2 xy;
  final double hdg;
}

const hitRadiusM = 0.40;
const fallbackCone = 25 * math.pi / 180;

Vec2 worldDirection(Vec2 local, double heading) {
  final unit = local.unit();
  final c = math.cos(heading);
  final s = math.sin(heading);
  return Vec2(unit.y * c - unit.x * s, unit.y * s + unit.x * c);
}

Vec2 screenDirection(Vec2 world, double heading) {
  final unit = world.unit();
  final c = math.cos(heading);
  final s = math.sin(heading);
  return Vec2(-unit.x * s + unit.y * c, unit.x * c + unit.y * s);
}

double angleBetween(Vec2 a, Vec2 b) {
  final d = a.unit().dot(b.unit()).clamp(-1.0, 1.0);
  return math.acos(d);
}

bool rayHitsCircle(Vec2 origin, Vec2 dir, Vec2 center, double radius) {
  final unit = dir.unit();
  final ox = origin.x - center.x;
  final oy = origin.y - center.y;
  final b = 2 * (ox * unit.x + oy * unit.y);
  final c = ox * ox + oy * oy - radius * radius;
  final disc = b * b - 4 * c;
  if (disc < 0) return false;
  final root = math.sqrt(disc);
  final t1 = (-b - root) / 2;
  final t2 = (-b + root) / 2;
  return t1 >= 0 || t2 >= 0;
}
