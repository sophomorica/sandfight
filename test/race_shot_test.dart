import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/draw/race.dart';
import 'package:sandfight/features/race/race_screen.dart';
import 'package:sandfight/features/zen/carve_screen.dart';
import 'package:sandfight/render/sand_field.dart';

void main() {
  testWidgets('free play and draw race sand', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final out = Directory('artifacts/sand')..createSync(recursive: true);
    await _shoot(tester, out, 'free-play', const CarveScreen(onLeave: _leave));
    await _shoot(
      tester,
      out,
      'draw-race',
      const RaceScreen(
        glyph: Glyph.circle,
        clock: Counting(45000),
        onStroke: _keep,
        onLeave: _leave,
      ),
    );
    expect(find.text('circle'), findsOneWidget);
    expect(find.byType(SandField), findsOneWidget);
    expect(find.byKey(const Key('my-mass')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

void _leave() {}

void _keep(Stroke stroke) {}

Future<void> _shoot(
  WidgetTester tester,
  Directory out,
  String name,
  Widget screen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(key: const Key('shot'), child: screen),
    ),
  );
  final frame = await _waitUntilLit(tester);
  File('${out.path}/$name.png').writeAsBytesSync(frame.png);
  final mirrorRoot = Directory('/opt/cursor/artifacts');
  if (mirrorRoot.existsSync()) {
    final mirrorDir = Directory('${mirrorRoot.path}/sand')
      ..createSync(recursive: true);
    File('${mirrorDir.path}/$name.png').writeAsBytesSync(frame.png);
  }
  // ignore: avoid_print
  print('RASTER $name ${frame.ms} ms ${frame.png.length} bytes');
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
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

Future<_Frame?> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot')),
  );
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
  return _Frame(
    png,
    raw,
    width,
    height,
    DateTime.now().difference(started).inMilliseconds,
  );
}
