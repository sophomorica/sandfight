import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/game/haptics.dart';
import 'package:sandfight/game/rules.dart';
import 'package:sandfight/game/throw_ray.dart';
import 'package:sandfight/net/fake_pose.dart';
import 'package:sandfight/net/pipe.dart';
import 'package:sandfight/net/session.dart';

void main() {
  const origin = Vec2(0.5, 1);
  const toward = Vec2(0, 1);
  const away = Vec2(0, -1);

  test('flick toward guest moves mass and taps the thrower', () {
    final link = MemoryLink();
    final host = HostLoop(link.host);
    final guest = GuestLoop(link.guest);
    host.start();
    guest.start();

    host.swipe(origin: origin, local: toward, speed: 1);

    expect(host.match.massOf(Seat.a), 88);
    expect(host.match.massOf(Seat.b), 112);
    expect(host.match.conserved, 200);
    expect(guest.match.massOf(Seat.a), 88);
    expect(guest.match.massOf(Seat.b), 112);
    expect(host.match.haptics.first.kind, HapticKind.lightTap);
    expect(host.match.haptics.first.seat, Seat.a);
    final buzz = host.match.haptics.where((event) => event.kind == HapticKind.sharpBuzz).single;
    expect(buzz.seat, Seat.b);
    expect(buzz.intensity > host.match.haptics.first.intensity, isTrue);
    expect(guest.match.haptics.where((event) => event.kind == HapticKind.sharpBuzz).single.seat, Seat.b);
  });

  test('flick away returns mass and keeps 200', () {
    final match = Match.opening();
    match.swipe(from: Seat.a, origin: origin, local: away, speed: 1);

    expect(match.massOf(Seat.a), 88);
    expect(match.massOf(Seat.b), 100);
    expect(match.conserved, 200);

    match.tick(800);

    expect(match.massOf(Seat.a), 100);
    expect(match.massOf(Seat.b), 100);
    expect(match.conserved, 200);
    expect(match.haptics.last.kind, HapticKind.rumble);
    expect(match.haptics.last.seat, Seat.a);
  });

  test('truck miss returns 25 and truck hit gives 25', () {
    final miss = Match.opening();
    miss.tick(20000);
    expect(miss.truck.owner, Seat.a);
    miss.aimTruck(from: Seat.a, local: away);
    expect(miss.massOf(Seat.a), 75);
    expect(miss.conserved, 200);
    miss.tick(800);
    expect(miss.massOf(Seat.a), 100);
    expect(miss.massOf(Seat.b), 100);
    expect(miss.conserved, 200);

    final hit = Match.opening();
    hit.tick(20000);
    hit.aimTruck(from: Seat.a, local: toward);
    hit.tick(600);
    expect(hit.massOf(Seat.a), 75);
    expect(hit.massOf(Seat.b), 125);
    expect(hit.conserved, 200);
    expect(hit.haptics.where((event) => event.kind == HapticKind.sharpBuzz).single.seat, Seat.b);
  });

  test('killing the link pauses then ends the match', () {
    final link = MemoryLink();
    final host = HostLoop(link.host);
    final guest = GuestLoop(link.guest);
    host.start();
    guest.start();
    guest.swipe(origin: origin, local: toward, speed: 1);
    expect(host.match.massOf(Seat.a), 112);
    expect(host.match.conserved, 200);

    link.kill();
    host.tick(2000);
    guest.tick(2000);

    expect(host.match.phase, Phase.paused);
    expect(host.match.banner, 'Get closer.');
    expect(guest.match.phase, Phase.paused);

    host.tick(8000);
    guest.tick(8000);

    expect(host.match.phase, Phase.ended);
    expect(host.match.endReason, EndReason.link);
    expect(guest.match.phase, Phase.ended);
    expect(guest.match.endReason, EndReason.link);
  });

  test('a phone without UWB still starts and uses the angle test', () {
    final link = MemoryLink();
    final host = HostLoop(link.host, uwb: true);
    final guest = GuestLoop(link.guest);
    host.start();
    guest.start();
    expect(host.match.phase, Phase.live);

    guest.sendPose(FakePose.guest, uwb: false);
    expect(host.match.aim, AimMode.fallback);

    final near = 20 * math.pi / 180;
    host.swipe(origin: origin, local: Vec2(math.sin(near), math.cos(near)), speed: 1);
    expect(host.match.massOf(Seat.b), 112);
    expect(host.match.conserved, 200);

    final wide = Match.opening(aim: AimMode.fallback);
    final far = 40 * math.pi / 180;
    wide.swipe(from: Seat.a, origin: origin, local: Vec2(math.sin(far), math.cos(far)), speed: 1);
    wide.tick(800);
    expect(wide.massOf(Seat.a), 100);
    expect(wide.massOf(Seat.b), 100);
    expect(wide.phase, Phase.live);
  });

  test('turning in place swings the ray with the heading', () {
    final match = Match.opening();
    match.setPose(Seat.a, Pose(const Vec2(-0.8, 0), math.pi));
    match.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
    match.tick(800);
    expect(match.massOf(Seat.a), 100);
    expect(match.massOf(Seat.b), 100);

    match.setPose(Seat.a, const Pose(Vec2(-0.8, 0), 0));
    match.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
    expect(match.massOf(Seat.a), 88);
    expect(match.massOf(Seat.b), 112);
    expect(match.conserved, 200);
  });

  test('loss descends on the buried phone and a fuller pile rumbles harder', () {
    final full = Match.opening();
    full.swipe(from: Seat.a, origin: origin, local: away, speed: 1);
    full.tick(800);
    final fullRumble = full.haptics.lastWhere((event) => event.kind == HapticKind.rumble).intensity;

    final light = Match.opening();
    var guard = 0;
    while (light.massOf(Seat.a) > 20 && guard < 20) {
      light.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
      guard += 1;
    }
    light.swipe(from: Seat.a, origin: origin, local: away, speed: 1);
    light.tick(800);
    final lightRumble = light.haptics.lastWhere((event) => event.kind == HapticKind.rumble).intensity;
    expect(fullRumble > lightRumble, isTrue);

    final bury = Match.opening();
    guard = 0;
    while (bury.phase != Phase.ended && guard < 20) {
      bury.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
      guard += 1;
    }
    expect(bury.massOf(Seat.a), 0);
    expect(bury.massOf(Seat.b), 200);
    expect(bury.winner, Seat.a);
    expect(bury.conserved, 200);
    final loss = bury.haptics.last;
    expect(loss.kind, HapticKind.descend);
    expect(loss.seat, Seat.b);
    expect(loss.pattern[0] > loss.pattern[1], isTrue);
    expect(loss.pattern[1] > loss.pattern[2], isTrue);
  });

  test('timer gives the match to whoever dumped more, else sudden death', () {
    final dumped = Match.opening();
    dumped.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
    dumped.tick(90000);
    expect(dumped.winner, Seat.a);
    expect(dumped.endReason, EndReason.time);

    final tied = Match.opening();
    tied.tick(90000);
    expect(tied.phase, Phase.overtime);
    tied.swipe(from: Seat.a, origin: origin, local: toward, speed: 1);
    expect(tied.winner, Seat.a);
    expect(tied.phase, Phase.ended);
  });
}

class MemoryEnd implements BytePipe {
  MemoryEnd? peer;
  var open = true;
  final _in = StreamController<Uint8List>(sync: true);

  @override
  Stream<Uint8List> get inbound => _in.stream;

  @override
  void send(Uint8List payload) {
    if (!open || peer == null || !peer!.open) return;
    peer!._in.add(Uint8List.fromList(payload));
  }

  @override
  Future<void> close() async {
    open = false;
  }
}

class MemoryLink {
  MemoryLink() {
    host = MemoryEnd();
    guest = MemoryEnd();
    host.peer = guest;
    guest.peer = host;
  }

  late final MemoryEnd host;
  late final MemoryEnd guest;

  void kill() {
    host.open = false;
    guest.open = false;
  }
}
