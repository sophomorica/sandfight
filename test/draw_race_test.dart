import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/draw/race.dart';

void main() {
  test('a sampled circle matches circle and not square', () {
    final stroke = _circle();
    expect(strokeMatches(Glyph.circle, stroke), isTrue);
    expect(strokeMatches(Glyph.square, stroke), isFalse);
    expect(strokeMatches(Glyph.triangle, stroke), isFalse);
  });

  test('a straight line matches nothing', () {
    final stroke = _line();
    expect(strokeMatches(Glyph.circle, stroke), isFalse);
    expect(strokeMatches(Glyph.square, stroke), isFalse);
    expect(strokeMatches(Glyph.triangle, stroke), isFalse);
  });

  test('a 4-point tap matches nothing', () {
    final stroke = _tap();
    expect(stroke.points, hasLength(4));
    expect(strokeMatches(Glyph.circle, stroke), isFalse);
    expect(strokeMatches(Glyph.square, stroke), isFalse);
    expect(strokeMatches(Glyph.triangle, stroke), isFalse);
  });

  test('a square matches square and a triangle matches triangle', () {
    expect(strokeMatches(Glyph.square, _square()), isTrue);
    expect(strokeMatches(Glyph.circle, _square()), isFalse);
    expect(strokeMatches(Glyph.triangle, _triangle()), isTrue);
    expect(strokeMatches(Glyph.square, _triangle()), isFalse);
  });

  test('solo round 0 locks the first correct time against the ghost', () {
    final ahead = _solo(3000, StrokeUp(_circle()));
    expect(ahead.glyph, Glyph.circle);
    expect(ahead.showing, Place.ahead);
    expect(ahead.clock, isA<Locked>());
    expect((ahead.clock as Locked).elapsedMs, 3000);

    final behind = _solo(9000, StrokeUp(_circle()));
    expect(behind.showing, Place.behind);
    expect((behind.clock as Locked).elapsedMs, 9000);

    final tied = _solo(8000, StrokeUp(_circle()));
    expect(tied.showing, Place.tied);
    expect((tied.clock as Locked).elapsedMs, 8000);

    final missed = _solo(45000, const ClockTick());
    expect(missed.showing, Place.behind);
    expect((missed.clock as Locked).elapsedMs, isNull);

    var ms = 0;
    final opened = RaceCaller.openSolo(round: 0, now: () => ms);
    expect(opened.glyph, Glyph.circle);
    expect(opened.showing, isNull);
    ms = 3000;
    final first = opened.turn(StrokeUp(_circle()));
    expect(opened.showing, isNull);
    expect((opened.clock as Counting).remainingMs, 42000);
    final second = first.turn(StrokeUp(_circle()));
    expect(second.showing, Place.ahead);
    expect((second.clock as Locked).elapsedMs, 3000);
  });

  test('a stroke at the limit does not score', () {
    final still = _solo(45000, StrokeUp(_circle()));
    expect(still.showing, isNull);
    expect(still.clock, isA<Counting>());
    final missed = still.turn(const ClockTick());
    expect(missed.showing, Place.behind);
    expect((missed.clock as Locked).elapsedMs, isNull);
  });

  test('a failed flush leaves the previous seat', () {
    var attempts = 0;
    final inbound = StreamController<Uint8List>();
    final port = RacePort(
      send: (_) {
        attempts += 1;
        if (attempts == 1) throw StateError('blocked');
      },
      inbound: inbound.stream,
    );
    var ms = 0;
    final seat = RaceCaller.openHost(round: 0, now: () => ms, port: port);
    ms = 3000;
    expect(() => seat.turn(StrokeUp(_circle())), throwsA(isA<StateError>()));
    expect(seat.showing, isNull);
    expect(seat.clock, isA<Counting>());
    final posted = seat.turn(StrokeUp(_circle()));
    expect(posted.showing, isNull);
    expect((posted.clock as Locked).elapsedMs, 3000);
    expect(attempts, 2);
  });

  test('the host writes the decision and the drawer applies it', () async {
    final toHost = StreamController<Uint8List>();
    final toGuest = StreamController<Uint8List>();
    final guestSent = <int>[];
    final hostPort = RacePort(send: toGuest.add, inbound: toHost.stream);
    final guestPort = RacePort(
      send: (bytes) {
        guestSent.add(bytes[0]);
        toHost.add(bytes);
      },
      inbound: toGuest.stream,
    );
    addTearDown(() async {
      await hostPort.close();
      await guestPort.close();
      await toHost.close();
      await toGuest.close();
    });
    var hostMs = 0;
    var guestMs = 0;
    RaceSeat host = RaceCaller.openHost(
      round: 0,
      now: () => hostMs,
      port: hostPort,
    );
    RaceSeat guest = RaceDrawer.open(
      round: 0,
      now: () => guestMs,
      port: guestPort,
    );
    hostPort.listen((input) => host = host.turn(input));
    guestPort.listen((input) => guest = guest.turn(input));

    hostMs = 3000;
    host = host.turn(StrokeUp(_circle()));
    guestMs = 5000;
    guest = guest.turn(StrokeUp(_circle()));
    await _drain();

    expect(host.showing, Place.ahead);
    expect((host.clock as Locked).elapsedMs, 3000);
    expect(guest.showing, Place.behind);
    expect((guest.clock as Locked).elapsedMs, 5000);
    expect(guestSent, [0x56]);
  });

  test('bury bytes do not finish a race', () async {
    final inbound = StreamController<Uint8List>();
    addTearDown(inbound.close);
    final port = RacePort(send: (_) {}, inbound: inbound.stream);
    addTearDown(port.close);
    var ms = 0;
    RaceSeat seat = RaceCaller.openHost(round: 0, now: () => ms, port: port);
    port.listen((input) => seat = seat.turn(input));
    inbound.add(Uint8List.fromList(const [0x53, 1, 0, 0]));
    inbound.add(Uint8List.fromList(const [0x49, 1]));
    inbound.add(Uint8List(2));
    inbound.add(Uint8List.fromList(const [0x56, 2, 1, 1, 0, 0, 0, 1]));
    await _drain();
    expect(seat.showing, isNull);
    expect(seat.clock, isA<Counting>());
  });
}

RaceSeat _solo(int elapsed, RaceInput input) {
  var ms = 0;
  final seat = RaceCaller.openSolo(round: 0, now: () => ms);
  ms = elapsed;
  return seat.turn(input);
}

Future<void> _drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Stroke _circle() {
  const count = 72;
  const cx = 200.0;
  const cy = 180.0;
  const radius = 90.0;
  return Stroke([
    for (var i = 0; i < count; i++)
      DrawPoint(
        cx + radius * math.cos(2 * math.pi * i / count),
        cy + radius * math.sin(2 * math.pi * i / count),
      ),
  ]);
}

Stroke _line() {
  return Stroke([for (var i = 0; i < 36; i++) DrawPoint(30.0 + i * 5, 80)]);
}

Stroke _tap() {
  return const Stroke([
    DrawPoint(10, 10),
    DrawPoint(14, 12),
    DrawPoint(12, 16),
    DrawPoint(9, 13),
  ]);
}

Stroke _square() {
  return Stroke(_regular(4, cx: 150, cy: 170, radius: 90, spin: 0.4));
}

Stroke _triangle() {
  return Stroke(_regular(3, cx: 160, cy: 180, radius: 100, spin: -math.pi / 2));
}

List<DrawPoint> _regular(
  int sides, {
  required double cx,
  required double cy,
  required double radius,
  required double spin,
}) {
  final corners = [
    for (var k = 0; k < sides; k++)
      DrawPoint(
        cx + radius * math.cos(spin + k * 2 * math.pi / sides),
        cy + radius * math.sin(spin + k * 2 * math.pi / sides),
      ),
  ];
  return _loop(corners, 28);
}

List<DrawPoint> _loop(List<DrawPoint> corners, int steps) {
  final points = <DrawPoint>[];
  for (var edge = 0; edge < corners.length; edge++) {
    final start = corners[edge];
    final end = corners[(edge + 1) % corners.length];
    for (var i = 0; i < steps; i++) {
      final t = i / steps;
      points.add(
        DrawPoint(
          start.x + (end.x - start.x) * t,
          start.y + (end.y - start.y) * t,
        ),
      );
    }
  }
  return points;
}
