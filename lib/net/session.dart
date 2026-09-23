import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game/rules.dart';
import '../game/throw_ray.dart';
import 'pipe.dart';
import 'protocol.dart';

const snapshotEveryMs = 83;
const poseEveryMs = 80;

class HostLoop {
  HostLoop(this.pipe, {bool uwb = true}) : match = Match.opening(aim: uwb ? AimMode.uwb : AimMode.fallback);

  final BytePipe pipe;
  final Match match;
  int silenceMs = 0;
  int _sinceSnap = 0;
  StreamSubscription<Uint8List>? _sub;

  void start() {
    _sub = pipe.inbound.listen(_onFrame);
  }

  void swipe({required Vec2 origin, required Vec2 local, required double speed}) {
    match.swipe(from: Seat.a, origin: origin, local: local, speed: speed);
    _push();
  }

  void aimTruck(Vec2 local) {
    match.aimTruck(from: Seat.a, local: local);
    _push();
  }

  void rematch() {
    match.rematch();
    _push();
  }

  void tick(int dtMs) {
    silenceMs += dtMs;
    match.noteSilence(silenceMs);
    match.tick(dtMs);
    _sinceSnap += dtMs;
    if (_sinceSnap >= snapshotEveryMs) {
      _sinceSnap = 0;
      _push();
    }
  }

  void _onFrame(Uint8List frame) {
    silenceMs = 0;
    match.noteSilence(0);
    final intent = decodeIntent(frame);
    if (intent == null) return;
    switch (intent) {
      case PoseIntent(:final seat, :final pose, :final uwb):
        if (seat != Seat.b) return;
        match.setPose(Seat.b, pose);
        match.noteUwb(uwb);
      case SwipeIntent(:final seat, :final origin, :final local, :final speed):
        if (seat != Seat.b) return;
        match.swipe(from: Seat.b, origin: origin, local: local, speed: speed);
      case TruckIntent(:final seat, :final local):
        if (seat != Seat.b) return;
        match.aimTruck(from: Seat.b, local: local);
      case RematchIntent():
        match.rematch();
    }
    _push();
  }

  void _push() {
    match.seq += 1;
    final events = match.drainHaptics();
    pipe.send(encodeSnapshot(match, events));
  }

  Future<void> close() async {
    await _sub?.cancel();
  }
}

class GuestLoop {
  GuestLoop(this.pipe) : match = Match.opening();

  final BytePipe pipe;
  final Match match;
  int silenceMs = 0;
  StreamSubscription<Uint8List>? _sub;
  void Function()? onChange;

  void start() {
    _sub = pipe.inbound.listen(_onFrame);
  }

  void swipe({required Vec2 origin, required Vec2 local, required double speed}) {
    pipe.send(encodeIntent(SwipeIntent(Seat.b, origin, local, speed)));
  }

  void aimTruck(Vec2 local) {
    pipe.send(encodeIntent(TruckIntent(Seat.b, local)));
  }

  void sendPose(Pose pose, {required bool uwb}) {
    pipe.send(encodeIntent(PoseIntent(Seat.b, pose, uwb)));
  }

  void rematch() {
    pipe.send(encodeIntent(RematchIntent()));
  }

  void tick(int dtMs) {
    silenceMs += dtMs;
    if (silenceMs >= 10000) {
      match.forceLinkEnd();
    } else if (silenceMs >= 2000) {
      match.forcePause();
    }
  }

  void _onFrame(Uint8List frame) {
    final view = decodeSnapshot(frame);
    if (view == null) return;
    silenceMs = 0;
    match.adopt(view);
    onChange?.call();
  }

  Future<void> close() async {
    await _sub?.cancel();
  }
}

class LocalDrive extends ChangeNotifier {
  LocalDrive({AimMode aim = AimMode.uwb}) : match = Match.opening(aim: aim);

  final Match match;
  Seat seat = Seat.a;

  void swipe({required Vec2 origin, required Vec2 local, required double speed}) {
    match.swipe(from: seat, origin: origin, local: local, speed: speed);
    notifyListeners();
  }

  void aimTruck(Vec2 local) {
    match.aimTruck(from: seat, local: local);
    notifyListeners();
  }

  void tick(int dtMs) {
    match.tick(dtMs);
    notifyListeners();
  }

  void rematch() {
    match.rematch();
    notifyListeners();
  }

  Future<void> close() async {}
}

class HostDrive extends ChangeNotifier {
  HostDrive(BytePipe pipe, {required bool uwb}) : loop = HostLoop(pipe, uwb: uwb) {
    loop.start();
  }

  final HostLoop loop;
  Match get match => loop.match;
  final seat = Seat.a;

  void swipe({required Vec2 origin, required Vec2 local, required double speed}) {
    loop.swipe(origin: origin, local: local, speed: speed);
    notifyListeners();
  }

  void aimTruck(Vec2 local) {
    loop.aimTruck(local);
    notifyListeners();
  }

  void tick(int dtMs) {
    loop.tick(dtMs);
    notifyListeners();
  }

  void rematch() {
    loop.rematch();
    notifyListeners();
  }

  Future<void> close() => loop.close();
}

class GuestDrive extends ChangeNotifier {
  GuestDrive(BytePipe pipe) : loop = GuestLoop(pipe) {
    loop.onChange = notifyListeners;
    loop.start();
  }

  final GuestLoop loop;
  Match get match => loop.match;
  final seat = Seat.b;
  int _poseAcc = 0;

  void swipe({required Vec2 origin, required Vec2 local, required double speed}) {
    loop.swipe(origin: origin, local: local, speed: speed);
  }

  void aimTruck(Vec2 local) => loop.aimTruck(local);

  void tick(int dtMs, {Pose? pose, bool uwb = false}) {
    _poseAcc += dtMs;
    if (pose != null && _poseAcc >= poseEveryMs) {
      _poseAcc = 0;
      loop.sendPose(pose, uwb: uwb);
    }
    loop.tick(dtMs);
    notifyListeners();
  }

  void rematch() => loop.rematch();

  Future<void> close() => loop.close();
}
