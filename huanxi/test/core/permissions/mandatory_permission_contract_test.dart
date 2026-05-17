import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mandatory permission gate is part of logged-in routing', () {
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();

    expect(router, contains("mandatoryPermissions = '/mandatory-permissions'"));
    expect(router, contains('MandatoryPermissionGatePage'));
    expect(
      router,
      contains('MandatoryPermissionService.instance.requiredGranted'),
    );
    expect(router, contains('return AppRoutes.mandatoryPermissions;'));
  });

  test('splash checks permissions before sending logged-in users to gate', () {
    final splash = File('lib/modules/auth/splash_page.dart').readAsStringSync();

    expect(splash, contains('MandatoryPermissionService.instance'));
    expect(splash, contains('.check();'));
    expect(splash, contains('permissionState.requiredGranted'));
    expect(splash, contains('context.go(AppRoutes.index)'));
  });

  test(
    'mandatory permission service only blocks entry on media permissions',
    () {
      final service = File(
        'lib/core/permissions/mandatory_permission_service.dart',
      ).readAsStringSync();

      expect(service, contains('bool get requiredGranted'));
      expect(service, contains('item.required && !item.granted'));
      expect(service, contains('Permission.camera'));
      expect(service, contains('Permission.microphone'));
      expect(service, contains('Permission.notification'));
      expect(service, contains('required: false'));
      expect(service, contains('CallKeepAliveBridge.isServiceRunning'));
      expect(service, contains('openAppSettings'));
    },
  );

  test('settings switch explicitly starts keep alive service', () {
    final service = File(
      'lib/core/permissions/mandatory_permission_service.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/modules/settings/settings_page.dart',
    ).readAsStringSync();

    expect(service, contains('startKeepAliveForLoggedInUser'));
    expect(service, contains('CallKeepAliveBridge.startOnlineMode'));
    expect(settings, contains('startKeepAliveForLoggedInUser'));
  });

  test('android foreground service bridge and settings entry exist', () {
    final bridge = File(
      'lib/core/device/call_keep_alive_bridge.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/modules/settings/settings_page.dart',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/huanxi/huanxi/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/huanxi/huanxi/CallKeepAliveService.kt',
    ).readAsStringSync();

    expect(bridge, contains('huanxi/call_keep_alive'));
    expect(settings, contains('后台接听模式'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_PHONE_CALL')));
    expect(manifest, isNot(contains('phoneCall')));
    expect(manifest, contains('CallKeepAliveService'));
    expect(activity, contains('startOnlineMode'));
    expect(activity, contains('result.error'));
    expect(service, contains('try {'));
    expect(service, contains('startForeground'));
  });

  test('background incoming call uses android system notification bridge', () {
    final bridge = File(
      'lib/core/device/incoming_call_notification_bridge.dart',
    ).readAsStringSync();
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/huanxi/huanxi/MainActivity.kt',
    ).readAsStringSync();
    final notification = File(
      'android/app/src/main/kotlin/com/huanxi/huanxi/IncomingCallNotification.kt',
    ).readAsStringSync();

    expect(bridge, contains('huanxi/incoming_call_notification'));
    expect(bridge, contains('showIncomingCall'));
    expect(bridge, contains('cancelIncomingCall'));
    expect(bridge, contains('takeLaunchIncomingCall'));
    expect(shell, contains('IncomingCallNotificationBridge.configure'));
    expect(shell, contains('IncomingCallNotificationBridge.showIncomingCall'));
    expect(
      shell,
      contains('IncomingCallNotificationBridge.cancelIncomingCall'),
    );
    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    expect(notification, contains('CATEGORY_CALL'));
    expect(notification, contains('setFullScreenIntent'));
    expect(notification, contains('ACTION_INCOMING_CALL'));
    expect(activity, contains('huanxi/incoming_call_notification'));
    expect(activity, contains('takeLaunchIncomingCall'));
  });
}
