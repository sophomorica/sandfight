import 'dart:math' as math;

import '../game/throw_ray.dart';

class FakePose {
  static final host = Pose(const Vec2(-0.8, 0), 0);
  static final guest = Pose(const Vec2(0.8, 0), math.pi);
}
