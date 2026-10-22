import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sandfight/build_info.dart';
import 'package:sandfight/features/home/home_screen.dart';
import 'package:sandfight/telemetry/device_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceLog.instance.debugClear();
    _mockBundle('9.8.7', '42');
  });

  test('bundleVersion formats the bundle and throws when a part is empty', () async {
    expect(await bundleVersion(), '9.8.7 (42)');
    _mockBundle('', '42');
    expect(bundleVersion(), throwsStateError);
    _mockBundle('9.8.7', '');
    expect(bundleVersion(), throwsStateError);
  });

  test('counts sessions, rounds, inputs, throws, and keeps recent errors', () async {
    final log = DeviceLog.instance;
    await log.session();
    await log.roundStarted();
    await log.roundFinished();
    await log.input();
    await log.threw();
    await log.fault(StateError('down'), StackTrace.fromString('#0 main\n#1 other'));
    log.debugClear();
    await log.open();
    final snap = log.current;
    expect(snap.sessions, 1);
    expect(snap.roundsStarted, 1);
    expect(snap.roundsFinished, 1);
    expect(snap.inputs, 1);
    expect(snap.throwsMade, 1);
    expect(snap.faults.single.error, contains('Bad state: down'));
    expect(snap.faults.single.error, contains('#0 main'));
  });

  testWidgets('a long press on the version opens the device log', (tester) async {
    await DeviceLog.instance.session();
    await DeviceLog.instance.fault(StateError('radio'), StackTrace.empty);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(onFind: () {}, lastWinner: null)));
    expect(find.byKey(const Key('version-label')), findsOneWidget);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('version-label'))).data, '9.8.7 (42)');
    expect(find.text('1.0.0+4'), findsNothing);
    await tester.longPress(find.byKey(const Key('version-label')));
    await tester.pumpAndSettle();
    expect(find.text('Device log'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('stat-sessions'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('stat-throws'))).data, '0');
    expect(find.textContaining('Bad state: radio'), findsOneWidget);
  });

  testWidgets('five taps on the version open the device log', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen(onFind: () {}, lastWinner: null)));
    await tester.pump();
    final label = find.byKey(const Key('version-label'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(label);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Device log'), findsOneWidget);
    expect(find.text('No errors yet.'), findsOneWidget);
  });
}

void _mockBundle(String version, String buildNumber) {
  PackageInfo.setMockInitialValues(
    appName: 'Sandfight',
    packageName: 'com.narrowroad.sandfight',
    version: version,
    buildNumber: buildNumber,
    buildSignature: 'test',
  );
}
