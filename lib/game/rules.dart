import 'dart:math' as math;

import 'arena.dart';
import 'haptics.dart';
import 'sand_grid.dart';
import 'throw_ray.dart';
import 'truck.dart';
import '../net/fake_pose.dart';

enum AimMode { uwb, fallback }

enum Phase { live, paused, overtime, ended }

enum EndReason { none, bury, time, draw, link }

class Pour {
  Pour(this.seat, this.total);

  final Seat seat;
  final int total;
  int delivered = 0;
  int elapsedMs = 0;

  int get left => total - delivered;
}

int throwMass(double speed01, int held) {
  if (held <= 0) return 0;
  final speed = speed01.clamp(0.0, 1.0);
  return math.min((4 + 8 * speed).round(), held);
}

class Match {
  Match.opening({this.aim = AimMode.uwb})
    : gridA = SandGrid.pile(100),
      gridB = SandGrid.pile(100),
      poseA = FakePose.host,
      poseB = FakePose.guest;

  AimMode aim;
  Phase phase = Phase.live;
  EndReason endReason = EndReason.none;
  Seat? winner;
  int tMs = 0;
  int seq = 0;
  int impactGen = 0;
  Seat? impactSeat;
  int overtimeAt = 0;
  int silenceMs = 0;

  SandGrid gridA;
  SandGrid gridB;
  Pose poseA;
  Pose poseB;
  final truck = Truck();
  final pours = <Pour>[];
  final haptics = <HapticEvent>[];
  final pendingHaptics = <HapticEvent>[];

  Phase _resume = Phase.live;
  Seat _nextOwner = Seat.a;
  int _nextTruckMs = 20000;
  bool _lossPlayed = false;

  int massOf(Seat seat) => _grid(seat).mass;

  int pourOf(Seat seat) => pours.where((pour) => pour.seat == seat).fold<int>(0, (sum, pour) => sum + pour.left);

  int get conserved =>
      gridA.mass + gridB.mass + pours.fold<int>(0, (sum, pour) => sum + pour.left) + truck.cargo;

  String? get banner => phase == Phase.paused ? 'Get closer.' : null;

  int get remainingMs {
    if (phase == Phase.overtime) return math.max(0, 15000 - (tMs - overtimeAt));
    return math.max(0, 90000 - tMs);
  }

  SandGrid gridFor(Seat seat) => _grid(seat);

  Pose poseFor(Seat seat) => seat == Seat.a ? poseA : poseB;

  bool get canAct => phase == Phase.live || phase == Phase.overtime;

  void noteUwb(bool supported) {
    if (!supported) aim = AimMode.fallback;
  }

  void setPose(Seat seat, Pose pose) {
    if (seat == Seat.a) {
      poseA = pose;
    } else {
      poseB = pose;
    }
    _applyPresence();
  }

  void noteSilence(int ms) {
    silenceMs = ms;
    _applyPresence();
  }

  void swipe({required Seat from, required Vec2 origin, required Vec2 local, required double speed}) {
    if (!canAct || local.length < 1e-6) return;
    final held = massOf(from);
    final want = throwMass(speed, held);
    if (want <= 0) return;
    _emit(HapticKind.lightTap, from, held);
    final got = _grid(from).takeNear(origin.x, origin.y, want);
    if (got <= 0) return;
    if (_hits(from, local)) {
      _give(otherSeat(from), got);
      _onTransfer(from);
    } else {
      pours.add(Pour(from, got));
    }
    _checkBury();
    _guard();
  }

  void aimTruck({required Seat from, required Vec2 local}) {
    if (!canAct || truck.phase != TruckPhase.idle || truck.owner != from) return;
    if (local.length < 1e-6) return;
    final got = math.min(25, massOf(from));
    if (got <= 0) return;
    _grid(from).takeNear(0.5, 1, got);
    truck.dir = worldDirection(local, poseFor(from).hdg);
    truck.sinceMs = 0;
    _nextOwner = otherSeat(from);
    _nextTruckMs = tMs + 25000;
    if (_hits(from, local)) {
      truck.phase = TruckPhase.driving;
      truck.cargo = got;
    } else {
      truck.phase = TruckPhase.leaving;
      truck.cargo = 0;
      pours.add(Pour(from, got));
    }
    _guard();
  }

  void tick(int dtMs) {
    if (dtMs < 0 || phase == Phase.ended) return;
    _applyPresence();
    if (phase == Phase.paused || phase == Phase.ended) return;
    tMs += dtMs;
    _advancePours(dtMs);
    _advanceTruck(dtMs);
    _maybeSpawn();
    _checkTimer();
    _checkBury();
    _guard();
  }

  void rematch() {
    final keepAim = aim;
    final a = poseA;
    final b = poseB;
    gridA = SandGrid.pile(100);
    gridB = SandGrid.pile(100);
    poseA = a;
    poseB = b;
    aim = keepAim;
    phase = Phase.live;
    endReason = EndReason.none;
    winner = null;
    tMs = 0;
    impactGen = 0;
    impactSeat = null;
    overtimeAt = 0;
    silenceMs = 0;
    truck.phase = TruckPhase.none;
    truck.owner = null;
    truck.cargo = 0;
    truck.sinceMs = 0;
    pours.clear();
    haptics.clear();
    pendingHaptics.clear();
    _resume = Phase.live;
    _nextOwner = Seat.a;
    _nextTruckMs = 20000;
    _lossPlayed = false;
    _guard();
  }

  void forcePause() {
    if (phase == Phase.ended || phase == Phase.paused) return;
    _resume = phase;
    phase = Phase.paused;
  }

  void forceLinkEnd() {
    if (phase == Phase.ended) return;
    phase = Phase.ended;
    endReason = EndReason.link;
    winner = null;
  }

  List<HapticEvent> drainHaptics() {
    final out = List<HapticEvent>.of(pendingHaptics);
    pendingHaptics.clear();
    return out;
  }

  void adopt(SnapshotView view) {
    gridA = SandGrid.fromCells(view.gridA);
    gridB = SandGrid.fromCells(view.gridB);
    poseA = view.poseA;
    poseB = view.poseB;
    aim = view.aim;
    phase = view.phase;
    endReason = view.endReason;
    winner = view.winner;
    tMs = view.tMs;
    seq = view.seq;
    impactGen = view.impactGen;
    impactSeat = view.impactSeat;
    overtimeAt = view.overtimeAt;
    truck.phase = view.truckPhase;
    truck.owner = view.truckOwner;
    truck.cargo = view.truckCargo;
    truck.dir = view.truckDir;
    pours
      ..clear()
      ..addAll([
        if (view.pourA > 0) Pour(Seat.a, view.pourA),
        if (view.pourB > 0) Pour(Seat.b, view.pourB),
      ]);
    haptics.addAll(view.haptics);
  }

  SandGrid _grid(Seat seat) => seat == Seat.a ? gridA : gridB;

  void _give(Seat seat, int mass) {
    _grid(seat).addBottom(mass);
    impactGen += 1;
    impactSeat = seat;
    _emit(HapticKind.sharpBuzz, seat, massOf(seat));
  }

  void _onTransfer(Seat from) {
    if (phase != Phase.overtime) return;
    winner = from;
    phase = Phase.ended;
    endReason = EndReason.bury;
    _maybeLoss();
  }

  bool _hits(Seat from, Vec2 local) {
    final me = poseFor(from);
    final them = poseFor(otherSeat(from));
    final dir = worldDirection(local, me.hdg);
    final toThem = them.xy - me.xy;
    if (aim == AimMode.fallback) {
      if (toThem.length < 1e-6) return false;
      return angleBetween(dir, toThem) <= fallbackCone;
    }
    return rayHitsCircle(me.xy, dir, them.xy, hitRadiusM);
  }

  void _advancePours(int dt) {
    for (final pour in pours) {
      pour.elapsedMs += dt;
      final due = pour.elapsedMs >= 800 ? pour.total : pour.total * pour.elapsedMs ~/ 800;
      final give = math.max(0, due - pour.delivered);
      if (give == 0) continue;
      _grid(pour.seat).addBottom(give);
      pour.delivered += give;
      if (pour.left == 0) _emit(HapticKind.rumble, pour.seat, massOf(pour.seat));
    }
    pours.removeWhere((pour) => pour.left == 0);
  }

  void _advanceTruck(int dt) {
    if (truck.phase == TruckPhase.idle) {
      truck.sinceMs += dt;
      if (truck.sinceMs >= 25000 && truck.owner != null) {
        _nextOwner = otherSeat(truck.owner!);
        _nextTruckMs = tMs;
        truck.phase = TruckPhase.none;
        truck.owner = null;
        truck.cargo = 0;
      }
      return;
    }
    if (truck.phase == TruckPhase.driving) {
      truck.sinceMs += dt;
      if (truck.sinceMs >= 600 && truck.owner != null && truck.cargo > 0) {
        final target = otherSeat(truck.owner!);
        final cargo = truck.cargo;
        truck.cargo = 0;
        truck.phase = TruckPhase.none;
        truck.owner = null;
        _give(target, cargo);
        _onTransfer(otherSeat(target));
      }
    } else if (truck.phase == TruckPhase.leaving) {
      truck.sinceMs += dt;
      if (truck.sinceMs >= 800) {
        truck.phase = TruckPhase.none;
        truck.owner = null;
      }
    }
  }

  void _maybeSpawn() {
    if (!canAct || truck.on || tMs < _nextTruckMs) return;
    truck.phase = TruckPhase.idle;
    truck.owner = _nextOwner;
    truck.cargo = 0;
    truck.sinceMs = 0;
    truck.dir = const Vec2(0, 1);
  }

  void _checkTimer() {
    if (phase == Phase.live && tMs >= 90000) {
      _settle();
      final a = gridA.mass;
      final b = gridB.mass;
      if (b > a) {
        winner = Seat.a;
        phase = Phase.ended;
        endReason = EndReason.time;
      } else if (a > b) {
        winner = Seat.b;
        phase = Phase.ended;
        endReason = EndReason.time;
      } else {
        phase = Phase.overtime;
        overtimeAt = tMs;
      }
      _maybeLoss();
      return;
    }
    if (phase == Phase.overtime && tMs - overtimeAt >= 15000) {
      phase = Phase.ended;
      endReason = EndReason.draw;
      winner = null;
    }
  }

  void _settle() {
    for (final pour in pours) {
      if (pour.left > 0) _grid(pour.seat).addBottom(pour.left);
    }
    pours.clear();
    if (truck.cargo > 0 && truck.owner != null) {
      final seat = truck.phase == TruckPhase.driving ? otherSeat(truck.owner!) : truck.owner!;
      _grid(seat).addBottom(truck.cargo);
      truck.cargo = 0;
    }
    truck.phase = TruckPhase.none;
    truck.owner = null;
  }

  void _checkBury() {
    if (phase != Phase.live || pours.isNotEmpty || truck.cargo > 0) return;
    final a = gridA.mass;
    final b = gridB.mass;
    if (a <= 1 && b >= 199) {
      winner = Seat.a;
      phase = Phase.ended;
      endReason = EndReason.bury;
    } else if (b <= 1 && a >= 199) {
      winner = Seat.b;
      phase = Phase.ended;
      endReason = EndReason.bury;
    }
    _maybeLoss();
  }

  void _applyPresence() {
    if (phase == Phase.ended) return;
    if (silenceMs >= 10000) {
      phase = Phase.ended;
      endReason = EndReason.link;
      winner = null;
      return;
    }
    final outside = !Arena.contains(poseA.xy) || !Arena.contains(poseB.xy);
    if (outside || silenceMs >= 2000) {
      if (phase != Phase.paused) {
        _resume = phase;
        phase = Phase.paused;
      }
      return;
    }
    if (phase == Phase.paused) phase = _resume;
  }

  void _maybeLoss() {
    if (phase != Phase.ended || winner == null || _lossPlayed) return;
    _lossPlayed = true;
    final loser = otherSeat(winner!);
    _emit(HapticKind.descend, loser, massOf(loser));
  }

  void _emit(HapticKind kind, Seat seat, int pile) {
    final event = HapticEvent(kind, seat, intensityFor(kind, pile));
    haptics.add(event);
    pendingHaptics.add(event);
  }

  void _guard() {
    if (conserved != 200) {
      throw StateError('sand total $conserved');
    }
  }
}

class SnapshotView {
  SnapshotView({
    required this.seq,
    required this.tMs,
    required this.gridA,
    required this.gridB,
    required this.poseA,
    required this.poseB,
    required this.aim,
    required this.phase,
    required this.endReason,
    required this.winner,
    required this.impactGen,
    required this.impactSeat,
    required this.overtimeAt,
    required this.truckPhase,
    required this.truckOwner,
    required this.truckCargo,
    required this.truckDir,
    required this.pourA,
    required this.pourB,
    required this.haptics,
  });

  final int seq;
  final int tMs;
  final List<int> gridA;
  final List<int> gridB;
  final Pose poseA;
  final Pose poseB;
  final AimMode aim;
  final Phase phase;
  final EndReason endReason;
  final Seat? winner;
  final int impactGen;
  final Seat? impactSeat;
  final int overtimeAt;
  final TruckPhase truckPhase;
  final Seat? truckOwner;
  final int truckCargo;
  final Vec2 truckDir;
  final int pourA;
  final int pourB;
  final List<HapticEvent> haptics;
}
