import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screenshot security bridge exposes platform channel apply method', () {
    final bridge = File(
      'lib/core/device/screenshot_security_bridge.dart',
    ).readAsStringSync();
    final appInit = File(
      'lib/app/providers/auth_provider.dart',
    ).readAsStringSync();

    expect(bridge, contains('huanxi/screenshot_security'));
    expect(bridge, contains('apply'));
    expect(bridge, contains('androidPreventScreenshotEnabled'));
    expect(bridge, contains('iosPreventScreenshotEnabled'));
    expect(appInit, contains('ScreenshotSecurityBridge.apply'));
  });

  test('native platforms expose dynamic screenshot security channel', () {
    final activity = File(
      'android/app/src/main/kotlin/com/huanxi/huanxi/MainActivity.kt',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(activity, contains('huanxi/screenshot_security'));
    expect(activity, contains('applyScreenshotSecurity'));
    expect(activity, contains('window.clearFlags'));
    expect(
      activity,
      isNot(
        contains(
          'window.setFlags(\n            WindowManager.LayoutParams.FLAG_SECURE',
        ),
      ),
    );
    expect(appDelegate, contains('huanxi/screenshot_security'));
    expect(appDelegate, contains('iosPreventScreenshotEnabled'));
    expect(appDelegate, contains('iOS screenshot prevention placeholder'));
  });
}
