import 'throw_ray.dart';

enum TruckPhase { none, idle, driving, leaving }

class Truck {
  TruckPhase phase = TruckPhase.none;
  Seat? owner;
  int cargo = 0;
  int sinceMs = 0;
  Vec2 dir = const Vec2(0, 1);

  bool get on => phase != TruckPhase.none;

  int get stateCode => switch (phase) {
    TruckPhase.none => 0,
    TruckPhase.idle => 1,
    TruckPhase.driving => 2,
    TruckPhase.leaving => 3,
  };
}
