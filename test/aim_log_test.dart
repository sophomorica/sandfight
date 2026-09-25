import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/game/rules.dart';
import 'package:sandfight/game/throw_ray.dart';
import 'package:sandfight/net/fake_pose.dart';
import 'package:sandfight/telemetry/aim_log.dart';

void main() {
  test('a straight swipe at the guest is on target with no miss', () {
    final aim = assessThrow(
      local: const Vec2(0, 1),
      speed: 0.8,
      lengthPx: 120,
      durationMs: 90,
      me: FakePose.host,
      them: FakePose.guest,
      aim: AimMode.uwb,
    );
    expect(aim.angleDeg, 0);
    expect(aim.bearingDeg, 0);
    expect(aim.distance, closeTo(1.6, 1e-9));
    expect(aim.direction, 1);
    expect(aim.onTarget, 1);
    expect(aim.missDeg, 0);
    expect(aim.speed, 0.8);
    expect(aim.lengthPx, 120);
    expect(aim.durationMs, 90);
  });

  test('a right-angle swipe misses by 90 degrees and fallback has no direction', () {
    final aim = assessThrow(
      local: const Vec2(1, 0),
      speed: 0.4,
      lengthPx: 30,
      durationMs: 40,
      me: FakePose.host,
      them: FakePose.guest,
      aim: AimMode.fallback,
    );
    expect(aim.angleDeg, 90);
    expect(aim.bearingDeg, 0);
    expect(aim.missDeg, 90);
    expect(aim.onTarget, 0);
    expect(aim.direction, 0);
  });

  test('a zero-length target has no direction and still counts as a hit', () {
    const pose = Pose(Vec2(0, 0), 0);
    final aim = assessThrow(
      local: const Vec2(0, 1),
      speed: 1,
      lengthPx: 10,
      durationMs: 10,
      me: pose,
      them: pose,
      aim: AimMode.uwb,
    );
    expect(aim.distance, 0);
    expect(aim.direction, 0);
    expect(aim.onTarget, 1);
    expect(aim.bearingDeg, 0);
    expect(aim.missDeg, 0);
  });

  test('a round summary counts hits, misses, and the absolute miss', () {
    final round = AimRound();
    round.add(assessThrow(
      local: const Vec2(0, 1),
      speed: 1,
      lengthPx: 80,
      durationMs: 50,
      me: FakePose.host,
      them: FakePose.guest,
      aim: AimMode.uwb,
    ));
    round.add(assessThrow(
      local: const Vec2(1, 0),
      speed: 1,
      lengthPx: 80,
      durationMs: 50,
      me: FakePose.host,
      them: FakePose.guest,
      aim: AimMode.fallback,
    ));
    expect(round.summary(42000), {
      'throws': 2,
      'hits': 1,
      'misses': 1,
      'mean_miss': 45,
      'max_miss': 90,
      'no_direction': 1,
      'length_ms': 42000,
    });
    round.reset();
    expect(round.summary(0), {
      'throws': 0,
      'hits': 0,
      'misses': 0,
      'mean_miss': 0,
      'max_miss': 0,
      'no_direction': 0,
      'length_ms': 0,
    });
  });

  test('guest heading pi still treats up the screen as toward the host', () {
    final aim = assessThrow(
      local: const Vec2(0, 1),
      speed: 1,
      lengthPx: 10,
      durationMs: 10,
      me: FakePose.guest,
      them: FakePose.host,
      aim: AimMode.uwb,
    );
    expect(aim.bearingDeg, closeTo(0, 1e-9));
    expect(aim.onTarget, 1);
    expect(aim.missDeg.abs(), lessThan(1e-9));
    expect(aim.distance, closeTo(1.6, 1e-9));
  });
}