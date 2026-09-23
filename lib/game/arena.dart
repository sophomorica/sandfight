import 'throw_ray.dart';

class Arena {
  static const meters = 2.0;
  static const half = meters / 2;

  static bool contains(Vec2 point) => point.x.abs() <= half && point.y.abs() <= half;
}
