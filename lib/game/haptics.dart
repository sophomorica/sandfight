import 'throw_ray.dart';

enum HapticKind { lightTap, sharpBuzz, descend, rumble }

class HapticEvent {
  const HapticEvent(this.kind, this.seat, this.intensity);

  final HapticKind kind;
  final Seat seat;
  final double intensity;

  List<double> get pattern {
    if (kind != HapticKind.descend) return [intensity];
    return [intensity, intensity * 0.62, intensity * 0.28];
  }
}

double pileWeight(int mass) => mass.clamp(0, 200) / 200;

double intensityFor(HapticKind kind, int pileMass) {
  final weight = pileWeight(pileMass);
  return switch (kind) {
    HapticKind.lightTap => 0.40 * weight,
    HapticKind.sharpBuzz => 1.0 * weight,
    HapticKind.descend => 0.85 * weight,
    HapticKind.rumble => weight,
  };
}
