import 'dart:math' as math;

import '../game/rules.dart';
import '../game/throw_ray.dart';

class AimThrow {
  const AimThrow({
    required this.angleDeg,
    required this.speed,
    required this.lengthPx,
    required this.durationMs,
    required this.bearingDeg,
    required this.distance,
    required this.direction,
    required this.onTarget,
    required this.missDeg,
  });

  final double angleDeg;
  final double speed;
  final double lengthPx;
  final double durationMs;
  final double bearingDeg;
  final double distance;
  final int direction;
  final int onTarget;
  final double missDeg;

  Map<String, num> get data => {
    'angle_deg': angleDeg,
    'speed': speed,
    'length_px': lengthPx,
    'duration_ms': durationMs,
    'bearing_deg': bearingDeg,
    'distance': distance,
    'direction': direction,
    'on_target': onTarget,
    'miss_deg': missDeg,
  };
}

double swipeAngleDeg(Vec2 local) {
  if (local.length < 1e-9) return 0;
  return math.atan2(local.x, local.y) * 180 / math.pi;
}

AimThrow assessThrow({
  required Vec2 local,
  required double speed,
  required double lengthPx,
  required double durationMs,
  required Pose me,
  required Pose them,
  required AimMode aim,
}) {
  final toThem = them.xy - me.xy;
  final distance = toThem.length;
  final bearing = distance < 1e-9 ? 0.0 : swipeAngleDeg(screenDirection(toThem, me.hdg));
  final angle = swipeAngleDeg(local);
  final direction = aim == AimMode.uwb && distance >= 1e-6 ? 1 : 0;
  final dir = worldDirection(local, me.hdg);
  final hit = aim == AimMode.fallback
      ? distance >= 1e-6 && angleBetween(dir, toThem) <= fallbackCone
      : rayHitsCircle(me.xy, dir, them.xy, hitRadiusM);
  return AimThrow(
    angleDeg: angle,
    speed: speed,
    lengthPx: lengthPx,
    durationMs: durationMs,
    bearingDeg: bearing,
    distance: distance,
    direction: direction,
    onTarget: hit ? 1 : 0,
    missDeg: angle - bearing,
  );
}

class AimRound {
  int throws = 0;
  int hits = 0;
  int misses = 0;
  int noDirection = 0;
  double _absSum = 0;
  double _absMax = 0;

  void reset() {
    throws = 0;
    hits = 0;
    misses = 0;
    noDirection = 0;
    _absSum = 0;
    _absMax = 0;
  }

  void add(AimThrow aim) {
    throws += 1;
    if (aim.onTarget == 1) {
      hits += 1;
    } else {
      misses += 1;
    }
    if (aim.direction == 0) noDirection += 1;
    final miss = aim.missDeg.abs();
    _absSum += miss;
    if (miss > _absMax) _absMax = miss;
  }

  Map<String, num> summary(int lengthMs) => {
    'throws': throws,
    'hits': hits,
    'misses': misses,
    'mean_miss': throws == 0 ? 0 : _absSum / throws,
    'max_miss': _absMax,
    'no_direction': noDirection,
    'length_ms': lengthMs,
  };
}
