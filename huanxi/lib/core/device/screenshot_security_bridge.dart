import 'package:flutter/services.dart';

class ScreenshotSecurityBridge {
  static const MethodChannel _channel = MethodChannel(
    'huanxi/screenshot_security',
  );

  static Future<void> apply({
    required bool androidPreventScreenshotEnabled,
    required bool iosPreventScreenshotEnabled,
  }) async {
    await _channel.invokeMethod<void>('apply', {
      'androidPreventScreenshotEnabled': androidPreventScreenshotEnabled,
      'iosPreventScreenshotEnabled': iosPreventScreenshotEnabled,
    });
  }
}
