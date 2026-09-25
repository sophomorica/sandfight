import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'game_watch.dart';

enum AppScreen { home, search, match, result, blocked }

typedef GameRecord = void Function(String line);

class CrashReportingService {
  CrashReportingService({String? dsn, String? release, this.record})
    : dsn = dsn ?? const String.fromEnvironment('SENTRY_DSN'),
      release = release ?? const String.fromEnvironment('APP_RELEASE');

  static final instance = CrashReportingService();

  final String dsn;
  final String release;
  final GameRecord? record;
  int attempts = 0;

  SentryNavigatorObserver? _routes;

  bool get enabled => dsn.isNotEmpty;

  List<NavigatorObserver> get navigatorObservers {
    if (!enabled) return const [];
    return [_routes ??= SentryNavigatorObserver()];
  }

  Widget wrap(Widget child) {
    if (!enabled) return child;
    return SentryUserInteractionWidget(child: child);
  }

  Future<void> boot(Future<void> Function() appRunner) async {
    if (!enabled) {
      await appRunner();
      return;
    }
    await SentryFlutter.init((options) {
      configureSentry(options, dsn: dsn, release: release, releaseMode: kReleaseMode);
    }, appRunner: appRunner);
  }

  void screen(AppScreen screen) {
    _breadcrumb(GameSignal.screen, {'id': screen.index}, message: 'screen.${screen.name}');
  }

  void game(GameSignal signal, [Map<String, num> data = const {}]) {
    _breadcrumb(signal, data, message: signal.name);
  }

  void capability(int allowed) {
    game(GameSignal.capability, {'allowed': allowed});
  }

  Future<void> failure(GameSignal signal, [Map<String, num> data = const {}]) async {
    _breadcrumb(signal, data, message: signal.name);
    if (!enabled) return;
    attempts += 1;
    if (record != null) {
      record!('message:${signal.name}');
      return;
    }
    await Sentry.captureMessage(
      signal.name,
      level: SentryLevel.warning,
      withScope: (scope) async {
        await scope.setTag('game', signal.name);
        await scope.setContexts('game', data);
      },
    );
  }

  Future<void> handled(Object error, StackTrace stack, GameSignal signal, [Map<String, num> data = const {}]) async {
    _breadcrumb(signal, data, message: signal.name);
    if (!enabled) return;
    attempts += 1;
    if (record != null) {
      record!('exception:${signal.name}:${error.runtimeType}');
      return;
    }
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) async {
        await scope.setTag('game', signal.name);
        await scope.setContexts('game', data);
      },
    );
  }

  void _breadcrumb(GameSignal signal, Map<String, num> data, {required String message}) {
    if (!enabled) return;
    attempts += 1;
    final payload = Map<String, num>.unmodifiable(data);
    if (record != null) {
      record!('crumb:$message:${_pack(payload)}');
      return;
    }
    Sentry.addBreadcrumb(
      Breadcrumb(category: 'game', message: message, level: SentryLevel.info, data: payload),
    );
  }

  static String _pack(Map<String, num> data) {
    final keys = data.keys.toList()..sort();
    return keys.map((key) => '$key=${data[key]}').join(',');
  }
}

void configureSentry(SentryFlutterOptions options, {required String dsn, required String release, required bool releaseMode}) {
  options.dsn = dsn;
  if (release.isNotEmpty) options.release = release;
  options.environment = releaseMode ? 'production' : 'development';
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  options.tracesSampleRate = null;
  options.maxBreadcrumbs = 100;
  options.enableAutoSessionTracking = true;
  options.enableUserInteractionTracing = false;
  options.enableUserInteractionBreadcrumbs = true;
  options.beforeSend = _scrub;
}

Future<SentryEvent?> _scrub(SentryEvent event, Hint hint) async {
  event.user = null;
  event.contexts.device?.name = null;
  return event;
}
