import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/game/rules.dart';
import 'package:sandfight/telemetry/game_watch.dart';

MatchSample _sample({
  Phase phase = Phase.live,
  EndReason endReason = EndReason.none,
  AimMode aim = AimMode.uwb,
  int impactGen = 0,
  int silenceMs = 0,
  int tMs = 0,
  int winner = -1,
  int uwbSupported = 1,
}) {
  return MatchSample(
    phase: phase,
    endReason: endReason,
    aim: aim,
    impactGen: impactGen,
    silenceMs: silenceMs,
    tMs: tMs,
    winner: winner,
    players: 2,
    uwbSupported: uwbSupported,
  );
}

void main() {
  test('a new match records start, player count, and uwb', () {
    expect(watchMatch(null, _sample()), [
      const GameCrumb(GameSignal.matchStart, {'players': 2}),
      const GameCrumb(GameSignal.playerCount, {'players': 2}),
      const GameCrumb(GameSignal.roundStart, {'players': 2}),
      const GameCrumb(GameSignal.uwbStart, {'supported': 1, 'aim': 0}),
    ]);
  });

  test('fallback aim at open is a fallback crumb', () {
    final crumbs = watchMatch(null, _sample(aim: AimMode.fallback, uwbSupported: 0));
    expect(crumbs.last, const GameCrumb(GameSignal.fallback, {'aim': 1}));
  });

  test('a bury records the round end and an elimination', () {
    final live = _sample();
    final ended = _sample(phase: Phase.ended, endReason: EndReason.bury, tMs: 40000, winner: 1);
    expect(watchMatch(live, ended), [
      const GameCrumb(GameSignal.roundEnd, {'reason': 1, 't_ms': 40000}),
      const GameCrumb(GameSignal.matchEnd, {'reason': 1, 'players': 2, 'winner': 1}),
      const GameCrumb(GameSignal.elimination, {'winner': 1, 'reason': 1}),
    ]);
  });

  test('a lost link records a timeout and a lost peer', () {
    final live = _sample(silenceMs: 1500);
    final ended = _sample(phase: Phase.ended, endReason: EndReason.link, silenceMs: 10000, tMs: 10000);
    expect(watchMatch(live, ended), [
      const GameCrumb(GameSignal.roundEnd, {'reason': 4, 't_ms': 10000}),
      const GameCrumb(GameSignal.matchEnd, {'reason': 4, 'players': 2, 'winner': -1}),
      const GameCrumb(GameSignal.timeout, {'reason': 4, 'silence_ms': 10000}),
      const GameCrumb(GameSignal.peerLost, {'silence_ms': 10000, 'count': 2}),
    ]);
  });

  test('leaving uwb aim records fallback and invalidation', () {
    expect(watchMatch(_sample(), _sample(aim: AimMode.fallback)), [
      const GameCrumb(GameSignal.fallback, {'aim': 1}),
      const GameCrumb(GameSignal.uwbInvalidated, {'aim': 1}),
    ]);
  });

  test('a hit and a pause record impact and a distance gap', () {
    expect(watchMatch(_sample(), _sample(impactGen: 3, phase: Phase.paused, silenceMs: 2000)), [
      const GameCrumb(GameSignal.hit, {'impact': 3}),
      const GameCrumb(GameSignal.distanceGap, {'silence_ms': 2000}),
    ]);
  });

  test('peer count changes are counts only', () {
    expect(watchPeers(0, 2), [const GameCrumb(GameSignal.peerFound, {'count': 2})]);
    expect(watchPeers(2, 0), [const GameCrumb(GameSignal.peerLost, {'count': 0})]);
    expect(watchPeers(2, 2), isEmpty);
  });

  test('sampleMatch reads the open match without names', () {
    final sample = sampleMatch(Match.opening(aim: AimMode.fallback), players: 1, uwbSupported: 0);
    expect(sample.players, 1);
    expect(sample.aim, AimMode.fallback);
    expect(sample.winner, -1);
    expect(sample.phase, Phase.live);
  });
}
