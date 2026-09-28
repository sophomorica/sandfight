import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/features/match/match_screen.dart';
import 'package:sandfight/net/session.dart';
import 'package:sandfight/render/sand_field.dart';

void main() {
  testWidgets('aim on is labeled Aim ON and shows the measure hint', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final drive = LocalDrive();
    await tester.pumpWidget(MaterialApp(home: _ShotHarness(drive: drive)));
    await tester.pump();
    expect(find.text('Aim'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aim-toggle')));
    await tester.pump();
    expect(find.text('Aim ON'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('aim-hud'))).textSpan!.toPlainText(), contains('AIM ON'));
    expect(tester.widget<Text>(find.byKey(const Key('aim-hud'))).textSpan!.toPlainText(), contains('drag to measure'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('match sand after the brief strokes', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final out = Directory('artifacts/sand')..createSync(recursive: true);

    await _shoot(tester, out, 'up-30', 30, durationMs: 520);
    await _shoot(tester, out, 'up-0', 0, durationMs: 520);
    await _shoot(tester, out, 'up-minus-30', -30, durationMs: 520);
    await _shoot(tester, out, 'fast-flick', 0, durationMs: 110);
    await _shoot(tester, out, 'aim-live', 8, durationMs: 480, aim: true, release: false);
    await _shoot(tester, out, 'aim-summary', 8, durationMs: 480, aim: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _shoot(
  WidgetTester tester,
  Directory out,
  String name,
  double angleDeg, {
  required double durationMs,
  bool aim = false,
  bool release = true,
}) async {
  final drive = LocalDrive();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: const Key('shot'),
        child: _ShotHarness(drive: drive),
      ),
    ),
  );
  await _waitUntilLit(tester);
  if (aim) {
    await tester.tap(find.byKey(const Key('aim-toggle')));
    await tester.pump();
  }
  final rect = tester.getRect(find.byType(SandField));
  final stroke = _stroke(rect, angleDeg, durationMs);
  final gesture = await tester.startGesture(stroke.first.offset);
  for (var i = 1; i < stroke.length; i++) {
    await gesture.moveTo(stroke[i].offset, timeStamp: stroke[i].time);
  }
  if (release) await gesture.up(timeStamp: stroke.last.time);
  await tester.pump();
  final frame = await _waitUntilLit(tester);
  if (aim && release) {
    expect(tester.widget<Text>(find.byKey(const Key('aim-hud'))).textSpan!.toPlainText(), contains('avg'));
  }
  if (aim && !release) {
    expect(tester.widget<Text>(find.byKey(const Key('aim-hud'))).textSpan!.toPlainText(), contains('pt/s'));
  }
  File('${out.path}/$name.png').writeAsBytesSync(frame.png);
  final mirror = File('/opt/cursor/artifacts/sand/$name.png');
  if (mirror.parent.existsSync()) {
    mirror.writeAsBytesSync(frame.png);
  }
  // ignore: avoid_print
  print('RASTER $name ${frame.ms} ms ${frame.png.length} bytes');
  if (name == 'up-0') {
    expect(_grooveDarkerThanSand(frame, tester, stroke), isTrue);
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _Frame {
  const _Frame(this.png, this.raw, this.width, this.height, this.ms);
  final Uint8List png;
  final Uint8List raw;
  final int width;
  final int height;
  final int ms;
}

Future<_Frame> _waitUntilLit(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    final frame = await _capture(tester);
    if (frame != null && _differsFromFlat(frame.raw)) return frame;
  }
  fail('sand shader did not replace the flat bed');
}

bool _differsFromFlat(Uint8List bytes) {
  var off = 0;
  for (var n = 0; n < 40; n++) {
    final i = ((bytes.length ~/ 2 + n * 80) & ~3).clamp(0, bytes.length - 4);
    final dr = (bytes[i] - 205).abs();
    final dg = (bytes[i + 1] - 178).abs();
    final db = (bytes[i + 2] - 140).abs();
    if (dr + dg + db > 18) off++;
  }
  return off > 8;
}

bool _grooveDarkerThanSand(_Frame frame, WidgetTester tester, List<_Point> stroke) {
  final screen = tester.getTopLeft(find.byKey(const Key('shot')));
  final mid = stroke[stroke.length ~/ 2].offset - screen;
  double lum(Offset p) {
    final x = p.dx.round().clamp(0, frame.width - 1);
    final y = p.dy.round().clamp(0, frame.height - 1);
    final i = (y * frame.width + x) * 4;
    return frame.raw[i] * 0.3 + frame.raw[i + 1] * 0.5 + frame.raw[i + 2] * 0.2;
  }

  var darkest = lum(mid);
  for (var dy = -6; dy <= 6; dy += 3) {
    for (var dx = -14; dx <= 14; dx += 2) {
      final sample = lum(mid + Offset(dx.toDouble(), dy.toDouble()));
      if (sample < darkest) darkest = sample;
    }
  }
  final clear = lum(mid + const Offset(96, 0));
  return darkest + 24 < clear;
}

Future<_Frame?> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  final started = DateTime.now();
  final captured = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (raw == null || png == null) return null;
    return (raw.buffer.asUint8List(), png.buffer.asUint8List(), width, height);
  });
  if (captured == null) return null;
  final (raw, png, width, height) = captured;
  return _Frame(png, raw, width, height, DateTime.now().difference(started).inMilliseconds);
}

List<_Point> _stroke(Rect rect, double angleDeg, double durationMs) {
  final rad = angleDeg * math.pi / 180;
  final roomY = (rect.bottom - 80) - (rect.top + 36);
  final roomX = rect.width - 72;
  final cosA = math.cos(rad).abs();
  final sinA = math.sin(rad).abs();
  var length = cosA < 1e-6 ? roomY : roomY / cosA;
  if (sinA > 1e-6) length = math.min(length, roomX / sinA);
  final start = Offset(rect.center.dx - math.sin(rad) * length * 0.5, rect.bottom - 80);
  const count = 36;
  return [
    for (var i = 0; i < count; i++)
      _Point(
        start + Offset(math.sin(rad) * length * i / (count - 1), -math.cos(rad) * length * i / (count - 1)),
        Duration(milliseconds: (durationMs * i / (count - 1)).round()),
      ),
  ];
}

class _Point {
  const _Point(this.offset, this.time);
  final Offset offset;
  final Duration time;
}

class _ShotHarness extends StatefulWidget {
  const _ShotHarness({required this.drive});

  final LocalDrive drive;

  @override
  State<_ShotHarness> createState() => _ShotHarnessState();
}

class _ShotHarnessState extends State<_ShotHarness> {
  @override
  void initState() {
    super.initState();
    widget.drive.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MatchScreen(
      match: widget.drive.match,
      seat: widget.drive.seat,
      onSwipe: (origin, local, speed) => widget.drive.swipe(origin: origin, local: local, speed: speed),
      onTruck: widget.drive.aimTruck,
      onLeave: () {},
      onAim: (_) {},
    );
  }
}
