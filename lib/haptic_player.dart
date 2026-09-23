import 'package:flutter/services.dart';

import 'game/haptics.dart';

class HapticPlayer {
  static const _channel = MethodChannel('com.narrowroad.sandfight/ios');

  static Future<void> play(HapticEvent event) async {
    if (event.intensity <= 0) return;
    try {
      await _channel.invokeMethod<void>('play', {
        'kind': event.kind.name,
        'intensity': event.intensity,
        'pattern': event.pattern,
      });
    } on MissingPluginException {
      await _fallback(event);
    } catch (_) {
      await _fallback(event);
    }
  }

  static Future<String> machine() async {
    try {
      return await _channel.invokeMethod<String>('machine') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _fallback(HapticEvent event) async {
    switch (event.kind) {
      case HapticKind.lightTap:
        await HapticFeedback.lightImpact();
      case HapticKind.sharpBuzz:
        await HapticFeedback.mediumImpact();
      case HapticKind.rumble:
        await HapticFeedback.heavyImpact();
      case HapticKind.descend:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.lightImpact();
    }
  }
}
