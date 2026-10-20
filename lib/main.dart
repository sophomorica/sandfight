import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'telemetry/crash_reporting.dart';
import 'telemetry/device_log.dart';

Future<void> main() async {
  await CrashReportingService.instance.boot(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await DeviceLog.instance.open();
    await DeviceLog.instance.session();
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(DeviceLog.instance.fault(details.exception, details.stack));
      previousFlutter?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(DeviceLog.instance.fault(error, stack));
      return previousPlatform?.call(error, stack) ?? false;
    };
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    runApp(CrashReportingService.instance.wrap(const SandfightApp()));
  });
}
