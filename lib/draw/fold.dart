part of 'race.dart';

const int _raceLimitMs = 45000;
const int _ghostPaceMs = 8000;

Glyph _glyphForRound(int round) => Glyph.values[round % Glyph.values.length];

void _requireRound(int round) {
  if (round < 0) throw ArgumentError.value(round, 'round');
}

enum _Bench { caller, drawer }

sealed class _Mark {
  const _Mark(this.glyph);

  final Glyph glyph;
}

final class _Scored extends _Mark {
  const _Scored(super.glyph, this.elapsedMs);

  final int elapsedMs;
}

final class _Blank extends _Mark {
  const _Blank(super.glyph);
}

sealed class _Rival {
  const _Rival();
}

final class _Ghost extends _Rival {
  const _Ghost();
}

final class _Waiting extends _Rival {
  const _Waiting();
}

final class _Heard extends _Rival {
  const _Heard(this.mark);

  final _Mark mark;
}

sealed class _Life {
  const _Life();
}

final class _Drawing extends _Life {
  const _Drawing();
}

final class _Held extends _Life {
  const _Held(this.mark);

  final _Mark mark;
}

final class _Posted extends _Life {
  const _Posted(this.mark);

  final _Mark mark;
}

sealed class _Call {
  const _Call();
}

final class _CallOpen extends _Call {
  const _CallOpen();
}

final class _CallReady extends _Call {
  const _CallReady(this.decision);

  final _Decision decision;
}

final class _CallPosted extends _Call {
  const _CallPosted(this.decision);

  final _Decision decision;
}

sealed class _Decision {
  const _Decision();
}

final class _DrawDecision extends _Decision {
  const _DrawDecision();
}

final class _WinDecision extends _Decision {
  const _WinDecision(this.winner);

  final _Bench winner;
}

final class _Slate {
  const _Slate({
    required this.glyph,
    required this.shownAtMs,
    required this.life,
    required this.rival,
  });

  final Glyph glyph;
  final int shownAtMs;
  final _Life life;
  final _Rival rival;

  _Slate copy({_Life? life, _Rival? rival}) {
    return _Slate(
      glyph: glyph,
      shownAtMs: shownAtMs,
      life: life ?? this.life,
      rival: rival ?? this.rival,
    );
  }
}

final class _CallerStep {
  const _CallerStep(this.slate, this.call, this.mark, this.decision);

  final _Slate slate;
  final _Call call;
  final _Mark? mark;
  final _Decision? decision;
}

final class _DrawerStep {
  const _DrawerStep(this.slate, this.heard, this.mark);

  final _Slate slate;
  final _Decision? heard;
  final _Mark? mark;
}

_Decision _compare(_Mark local, _Mark remote) {
  return switch ((local, remote)) {
    (_Scored(elapsedMs: final left), _Scored(elapsedMs: final right)) =>
      left < right
          ? const _WinDecision(_Bench.caller)
          : left > right
          ? const _WinDecision(_Bench.drawer)
          : const _DrawDecision(),
    (_Scored(), _Blank()) => const _WinDecision(_Bench.caller),
    (_Blank(), _Scored()) => const _WinDecision(_Bench.drawer),
    (_Blank(), _Blank()) => const _DrawDecision(),
  };
}

_Mark _ghostAnswer(_Mark local) {
  // A miss still loses. The ghost is a scored 8000 ms mark either way.
  return _Scored(local.glyph, _ghostPaceMs);
}

int _elapsed(_Slate slate, RaceNow now) => now() - slate.shownAtMs;

_Mark? _heldMark(_Life life) => switch (life) {
  _Drawing() => null,
  _Held(:final mark) || _Posted(:final mark) => mark,
};

ClockFace _clock(_Slate slate, RaceNow now) {
  final mark = _heldMark(slate.life);
  if (mark is _Scored) return Locked(mark.elapsedMs);
  if (mark is _Blank) return const Locked(null);
  final left = _raceLimitMs - _elapsed(slate, now);
  return Counting(left < 0 ? 0 : left);
}

Place _view(_Decision decision, _Bench home) {
  return switch (decision) {
    _DrawDecision() => Place.tied,
    _WinDecision(:final winner) => winner == home ? Place.ahead : Place.behind,
  };
}

bool _scoreNow(_Slate slate, RaceNow now, Stroke stroke) {
  if (slate.life is! _Drawing) return false;
  final elapsed = _elapsed(slate, now);
  if (elapsed >= _raceLimitMs) return false;
  return strokeMatches(slate.glyph, stroke);
}

final class RaceCaller implements RaceSeat {
  RaceCaller._({
    required this._slate,
    required this._call,
    required this._now,
    required this._port,
  });

  final _Slate _slate;
  final _Call _call;
  final RaceNow _now;
  final RacePort? _port;

  static RaceCaller openSolo({required int round, required RaceNow now}) {
    _requireRound(round);
    return RaceCaller._(
      slate: _Slate(
        glyph: _glyphForRound(round),
        shownAtMs: now(),
        life: const _Drawing(),
        rival: const _Ghost(),
      ),
      call: const _CallOpen(),
      now: now,
      port: null,
    );
  }

  static RaceCaller openHost({
    required int round,
    required RaceNow now,
    required RacePort port,
  }) {
    _requireRound(round);
    return RaceCaller._(
      slate: _Slate(
        glyph: _glyphForRound(round),
        shownAtMs: now(),
        life: const _Drawing(),
        rival: const _Waiting(),
      ),
      call: const _CallOpen(),
      now: now,
      port: port,
    );
  }

  @override
  Glyph get glyph => _slate.glyph;

  @override
  ClockFace get clock => _clock(_slate, _now);

  @override
  Place? get showing {
    final decision = switch (_call) {
      _CallOpen() => null,
      _CallReady(:final decision) || _CallPosted(:final decision) => decision,
    };
    if (decision == null) return null;
    return _view(decision, _Bench.caller);
  }

  @override
  RaceSeat turn(RaceInput input) {
    final step = _step(input);
    if (step == null) return this;
    _port?._emit(step.mark, step.decision);
    final life = switch (step.slate.life) {
      _Held(:final mark) => _Posted(mark),
      final other => other,
    };
    final call = switch (step.call) {
      _CallReady(:final decision) => _CallPosted(decision),
      final other => other,
    };
    return RaceCaller._(
      slate: step.slate.copy(life: life),
      call: call,
      now: _now,
      port: _port,
    );
  }

  _CallerStep? _step(RaceInput input) {
    var slate = _slate;
    var call = _call;
    _Mark? queuedMark;
    var changed = false;
    switch (input) {
      case StrokeUp(:final stroke):
        if (_scoreNow(slate, _now, stroke)) {
          final mark = _Scored(slate.glyph, _elapsed(slate, _now));
          slate = slate.copy(life: _Held(mark));
          if (_port != null) queuedMark = mark;
          changed = true;
        }
      case ClockTick():
        if (slate.life is _Drawing && _elapsed(slate, _now) >= _raceLimitMs) {
          final mark = _Blank(slate.glyph);
          slate = slate.copy(life: _Held(mark));
          if (_port != null) queuedMark = mark;
          changed = true;
        }
      case _MarkHeard(:final mark):
        if (slate.rival is _Waiting && mark.glyph.id == slate.glyph.id) {
          slate = slate.copy(rival: _Heard(mark));
          changed = true;
        }
      case _DecisionHeard():
        break;
    }
    final local = _heldMark(slate.life);
    _Decision? queuedDecision;
    if (local != null && call is _CallOpen) {
      final remote = switch (slate.rival) {
        _Ghost() => _ghostAnswer(local),
        _Heard(:final mark) => mark,
        _Waiting() => null,
      };
      if (remote != null) {
        final decision = _compare(local, remote);
        call = _CallReady(decision);
        if (_port != null) queuedDecision = decision;
        changed = true;
      }
    }
    if (!changed) return null;
    return _CallerStep(slate, call, queuedMark, queuedDecision);
  }
}

final class RaceDrawer implements RaceSeat {
  RaceDrawer._({
    required this._slate,
    required this._heard,
    required this._now,
    required this._port,
  });

  final _Slate _slate;
  final _Decision? _heard;
  final RaceNow _now;
  final RacePort _port;

  static RaceDrawer open({
    required int round,
    required RaceNow now,
    required RacePort port,
  }) {
    _requireRound(round);
    return RaceDrawer._(
      slate: _Slate(
        glyph: _glyphForRound(round),
        shownAtMs: now(),
        life: const _Drawing(),
        rival: const _Waiting(),
      ),
      heard: null,
      now: now,
      port: port,
    );
  }

  @override
  Glyph get glyph => _slate.glyph;

  @override
  ClockFace get clock => _clock(_slate, _now);

  @override
  Place? get showing {
    final heard = _heard;
    if (heard == null) return null;
    return _view(heard, _Bench.drawer);
  }

  @override
  RaceSeat turn(RaceInput input) {
    final step = _step(input);
    if (step == null) return this;
    _port._emit(step.mark, null);
    final life = switch (step.slate.life) {
      _Held(:final mark) => _Posted(mark),
      final other => other,
    };
    return RaceDrawer._(
      slate: step.slate.copy(life: life),
      heard: step.heard,
      now: _now,
      port: _port,
    );
  }

  _DrawerStep? _step(RaceInput input) {
    var slate = _slate;
    var heard = _heard;
    _Mark? queuedMark;
    var changed = false;
    switch (input) {
      case StrokeUp(:final stroke):
        if (_scoreNow(slate, _now, stroke)) {
          final mark = _Scored(slate.glyph, _elapsed(slate, _now));
          slate = slate.copy(life: _Held(mark));
          queuedMark = mark;
          changed = true;
        }
      case ClockTick():
        if (slate.life is _Drawing && _elapsed(slate, _now) >= _raceLimitMs) {
          final mark = _Blank(slate.glyph);
          slate = slate.copy(life: _Held(mark));
          queuedMark = mark;
          changed = true;
        }
      case _MarkHeard():
        break;
      case _DecisionHeard(:final decision):
        if (heard == null) {
          heard = decision;
          changed = true;
        }
    }
    if (!changed) return null;
    return _DrawerStep(slate, heard, queuedMark);
  }
}
