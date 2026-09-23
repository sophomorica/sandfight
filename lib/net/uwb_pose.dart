import '../game/throw_ray.dart';
import 'fake_pose.dart';

class UwbPose {
  static const fake = bool.fromEnvironment('FAKE_UWB');

  static bool get supported => fake;

  static Pose forSeat(Seat seat) => seat == Seat.a ? FakePose.host : FakePose.guest;
}
