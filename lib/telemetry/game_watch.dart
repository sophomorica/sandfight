import '../game/rules.dart';
import '../game/throw_ray.dart';

enum GameSignal {
  screen,
  roundStart,
  roundEnd,
  matchStart,
  matchEnd,
  playerCount,
  uwbStart,
  peerFound,
  peerLost,
  distanceGap,
  uwbInvalidated,
  uwbError,
  capability,
  hit,
  elimination,
  timeout,
  fallback,
  permissionDenied,
  sessionError,
}

class GameCrumb {
  const GameCrumb(this.signal, [this.data = const {}]);

  final GameSignal signal;
  final Map<String, num> data;

  @override
  bool operator ==(Object other) =>
      other is GameCrumb && other.signal == signal && _same(other.data, data);

  @override
  int get hashCode => Object.hash(signal, Object.hashAll(data.entries.map((e) => Object.hash(e.key, e.value))));
}

bool _same(Map<String, num> a, Map<String, num> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

class MatchSample {
  const MatchSample({
    required this.phase,
    required this.endReason,
    required this.aim,
    required this.impactGen,
    required this.silenceMs,
    required this.tMs,
    required this.winner,
    required this.players,
    required this.uwbSupported,
  });

  final Phase phase;
  final EndReason endReason;
  final AimMode aim;
  final int impactGen;
  final int silenceMs;
  final int tMs;
  final int winner;
  final int players;
  final int uwbSupported;
}

MatchSample sampleMatch(Match match, {required int players, required int uwbSupported}) {
  final winner = match.winner;
  return MatchSample(
    phase: match.phase,
    endReason: match.endReason,
    aim: match.aim,
    impactGen: match.impactGen,
    silenceMs: match.silenceMs,
    tMs: match.tMs,
    winner: winner == null ? -1 : (winner == Seat.a ? 0 : 1),
    players: players,
    uwbSupported: uwbSupported,
  );
}

List<GameCrumb> watchMatch(MatchSample? previous, MatchSample next) {
  final out = <GameCrumb>[];
  if (previous == null) {
    out.add(GameCrumb(GameSignal.matchStart, {'players': next.players}));
    out.add(GameCrumb(GameSignal.playerCount, {'players': next.players}));
    out.add(GameCrumb(GameSignal.roundStart, {'players': next.players}));
    out.add(GameCrumb(GameSignal.uwbStart, {'supported': next.uwbSupported, 'aim': next.aim.index}));
    if (next.aim == AimMode.fallback) {
      out.add(const GameCrumb(GameSignal.fallback, {'aim': 1}));
    }
    return out;
  }
  if (previous.phase == Phase.ended && next.phase != Phase.ended) {
    out.add(GameCrumb(GameSignal.roundStart, {'players': next.players}));
  }
  if (previous.phase != Phase.ended && next.phase == Phase.ended) {
    out.add(GameCrumb(GameSignal.roundEnd, {'reason': next.endReason.index, 't_ms': next.tMs}));
    out.add(GameCrumb(GameSignal.matchEnd, {'reason': next.endReason.index, 'players': next.players, 'winner': next.winner}));
    if (next.endReason == EndReason.bury) {
      out.add(GameCrumb(GameSignal.elimination, {'winner': next.winner, 'reason': next.endReason.index}));
    }
    if (next.endReason == EndReason.time || next.endReason == EndReason.draw || next.endReason == EndReason.link) {
      out.add(GameCrumb(GameSignal.timeout, {'reason': next.endReason.index, 'silence_ms': next.silenceMs}));
    }
    if (next.endReason == EndReason.link) {
      out.add(GameCrumb(GameSignal.peerLost, {'silence_ms': next.silenceMs, 'count': next.players}));
    }
  }
  if (previous.aim != AimMode.fallback && next.aim == AimMode.fallback) {
    out.add(const GameCrumb(GameSignal.fallback, {'aim': 1}));
    out.add(const GameCrumb(GameSignal.uwbInvalidated, {'aim': 1}));
  }
  if (next.impactGen > previous.impactGen) {
    out.add(GameCrumb(GameSignal.hit, {'impact': next.impactGen}));
  }
  if (previous.phase != Phase.paused && next.phase == Phase.paused) {
    out.add(GameCrumb(GameSignal.distanceGap, {'silence_ms': next.silenceMs}));
  } else if (previous.silenceMs < 2000 && next.silenceMs >= 2000 && next.phase != Phase.ended) {
    out.add(GameCrumb(GameSignal.distanceGap, {'silence_ms': next.silenceMs}));
  }
  return out;
}

List<GameCrumb> watchPeers(int previous, int next) {
  if (next > previous) return [GameCrumb(GameSignal.peerFound, {'count': next})];
  if (next < previous) return [GameCrumb(GameSignal.peerLost, {'count': next})];
  return const [];
}
