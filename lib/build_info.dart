import 'package:package_info_plus/package_info_plus.dart';

Future<String> bundleVersion() async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.isEmpty || info.buildNumber.isEmpty) {
    throw StateError('bundle version is empty');
  }
  return '${info.version} (${info.buildNumber})';
}
