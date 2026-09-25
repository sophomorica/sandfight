import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/telemetry/crash_reporting.dart';
import 'package:sandfight/telemetry/game_watch.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('an empty DSN records nothing and does not throw', () async {
    final lines = <String>[];
    final service = CrashReportingService(dsn: '', record: lines.add);
    service.screen(AppScreen.home);
    service.game(GameSignal.hit, {'mass': 12});
    service.capability(0);
    await service.failure(GameSignal.permissionDenied, {'state': 2});
    await service.handled(StateError('down'), StackTrace.empty, GameSignal.sessionError, {'code': 4});
    expect(service.enabled, false);
    expect(service.attempts, 0);
    expect(lines, isEmpty);
    expect(service.navigatorObservers, isEmpty);
    expect(service.wrap(const Placeholder()).runtimeType.toString(), 'Placeholder');
  });

  test('a DSN records game breadcrumbs and handled failures in the sink', () async {
    final lines = <String>[];
    final service = CrashReportingService(
      dsn: 'https://public@example.ingest.sentry.io/1',
      release: 'sandfight@1.0.0+3',
      record: lines.add,
    );
    service.game(GameSignal.roundStart, {'players': 2});
    await service.failure(GameSignal.peerLost, {'count': 0});
    await service.handled(StateError('down'), StackTrace.empty, GameSignal.uwbError, {'code': 4});
    expect(lines, [
      'crumb:roundStart:players=2',
      'crumb:peerLost:count=0',
      'message:peerLost',
      'crumb:uwbError:code=4',
      'exception:uwbError:StateError',
    ]);
  });

  test('configureSentry keeps sessions and drops tracing and pii', () {
    final options = SentryFlutterOptions(dsn: 'https://public@example.ingest.sentry.io/1');
    configureSentry(options, dsn: 'https://public@example.ingest.sentry.io/1', release: 'sandfight@1.0.0+3', releaseMode: true);
    expect(options.release, 'sandfight@1.0.0+3');
    expect(options.environment, 'production');
    expect(options.sendDefaultPii, false);
    expect(options.attachScreenshot, false);
    expect(options.tracesSampleRate, isNull);
    expect(options.maxBreadcrumbs, 100);
    expect(options.enableAutoSessionTracking, true);
    expect(options.enableUserInteractionTracing, false);
    expect(options.enableUserInteractionBreadcrumbs, true);
  });
}
