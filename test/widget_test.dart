import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sandfight/app.dart';
import 'package:sandfight/features/home/home_screen.dart';
import 'package:sandfight/features/match/match_screen.dart';
import 'package:sandfight/net/session.dart';
import 'package:sandfight/render/sand_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Sandfight',
      packageName: 'com.narrowroad.sandfight',
      version: '9.8.7',
      buildNumber: '42',
      buildSignature: 'test',
    );
  });

  testWidgets('home shows find nearby and the last bury', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(onFind: () {}, onCarve: () {}, onRace: () {}, lastWinner: 'P2'),
      ),
    );
    expect(find.text('Find nearby players'), findsOneWidget);
    expect(find.text('Hold the phone up.'), findsOneWidget);
    expect(find.text('Flick sand toward the other phone.'), findsOneWidget);
    expect(find.text('Empty your pile to bury them.'), findsOneWidget);
    expect(find.text('Last bury: P2'), findsOneWidget);
    expect(find.text('Free play'), findsOneWidget);
    expect(find.text('Draw race'), findsOneWidget);
    await tester.pump();
    expect(find.text('9.8.7 (42)'), findsOneWidget);
    expect(find.text('1.0.0+4'), findsNothing);
  });

  testWidgets('iPhone 11 is refused and iPhone 12 reaches home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SandfightApp(machine: 'iPhone12,1'));
    await tester.pump();
    expect(find.text('Sandfight needs an iPhone 12 or newer.'), findsOneWidget);

    await tester.pumpWidget(const SandfightApp(machine: 'iPhone13,2'));
    await tester.pump();
    expect(find.text('Find nearby players'), findsOneWidget);
  });

  testWidgets('a flick up the pile moves 12 mass', (tester) async {
    final drive = LocalDrive();
    await tester.pumpWidget(MaterialApp(home: _Harness(drive: drive)));
    await tester.fling(find.byType(SandField), const Offset(0, -700), 5000);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('my-mass'))).data, '88');
    expect(tester.widget<Text>(find.byKey(const Key('their-mass'))).data, '112');
    expect(drive.match.conserved, 200);
  });

  testWidgets('a non-primary flick still moves 12 mass', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final drive = LocalDrive();
    await tester.pumpWidget(MaterialApp(home: _Harness(drive: drive)));
    await tester.pump();
    final field = tester.getRect(find.byType(SandField));
    final start = field.center;
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch, buttons: kSecondaryButton);
    await gesture.moveBy(const Offset(0, -420), timeStamp: const Duration(milliseconds: 30));
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('my-mass'))).data, '88');
    expect(tester.widget<Text>(find.byKey(const Key('their-mass'))).data, '112');
    expect(drive.match.conserved, 200);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('free play offers the garden tools and no race', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SandfightApp(machine: 'iPhone13,2'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('free-play')));
    await tester.pump();
    expect(find.byType(SandField), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-rake')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-smooth')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-reset')), findsOneWidget);
    expect(find.text('circle'), findsNothing);
    expect(find.text('Ahead'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+\.\d+s')), findsNothing);
    expect(find.byKey(const Key('my-mass')), findsNothing);
    expect(find.byKey(const Key('their-mass')), findsNothing);
  });

  testWidgets('a solo draw race names the glyph and hides pile mass', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SandfightApp(machine: 'iPhone13,2', fakeUwb: true));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('draw-race')));
    await tester.pump();
    await tester.pump();
    expect(find.text('circle'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-rake')), findsNothing);
    expect(find.byKey(const Key('my-mass')), findsNothing);
  });

  testWidgets('a circle on the solo race finishes ahead of the ghost', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SandfightApp(machine: 'iPhone13,2', fakeUwb: true));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('draw-race')));
    await tester.pump();
    await tester.pump();
    final field = tester.getRect(find.byType(SandField));
    final center = field.center;
    const radius = 90.0;
    final gesture = await tester.startGesture(center + const Offset(radius, 0));
    const steps = 72;
    for (var i = 1; i <= steps; i++) {
      final angle = 2 * math.pi * i / steps;
      await gesture.moveTo(center + Offset(radius * math.cos(angle), radius * math.sin(angle)));
    }
    await gesture.up();
    await tester.pump();
    expect(find.text('Ahead'), findsOneWidget);
    expect(find.byKey(const Key('my-mass')), findsNothing);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.drive});

  final LocalDrive drive;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
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
    );
  }
}
