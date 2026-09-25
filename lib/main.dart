import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'telemetry/crash_reporting.dart';

Future<void> main() async {
  await CrashReportingService.instance.boot(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    runApp(CrashReportingService.instance.wrap(const SandfightApp()));
  });
}
