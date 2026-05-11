import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('teen mode routes and storage keys are registered', () {
    final router = read('lib/app/routes/app_router.dart');
    final constants = read('lib/core/constants/app_constants.dart');

    expect(router, contains("teenModeSetup = '/settings/teen-mode/setup'"));
    expect(router, contains("teenModeVerify = '/teen-mode/verify'"));
    expect(router, contains('TeenModeSetupPage'));
    expect(router, contains('TeenModeVerifyPage'));
    expect(router, contains('TeenModeService.instance.isLocked'));

    expect(constants, contains("storageTeenModeState = 'teen_mode_state'"));
    expect(constants, isNot(contains('storageTeenModeUnlocked')));
  });

  test('teen mode uses one atomic persisted state blob', () {
    final service = read('lib/services/teen_mode_service.dart');
    final constants = read('lib/core/constants/app_constants.dart');

    expect(constants, contains("storageTeenModeState = 'teen_mode_state'"));
    expect(service, contains('jsonEncode('));
    expect(service, contains('jsonDecode('));
    expect(service, contains('TeenModeRecord'));
    expect(service, isNot(contains('storageTeenModeEnabled')));
    expect(service, isNot(contains('storageTeenModeSalt')));
    expect(service, isNot(contains('storageTeenModePinHash')));
  });

  test('teen mode service stores hashed four digit pin and clears on verify', () {
    final service = read('lib/services/teen_mode_service.dart');

    expect(service, contains(r"RegExp(r'^\d{4}$')"));
    expect(service, contains('sha256.convert'));
    expect(service, contains('enable(String pin)'));
    expect(service, contains('verifyAndDisable(String pin)'));
    expect(service, contains('clear()'));
    expect(service, isNot(contains('unlocked')));
  });

  test('settings page uses real teen mode flow instead of placeholder', () {
    final settings = read('lib/modules/settings/settings_page.dart');

    expect(settings, contains('青少年模式'));
    expect(settings, contains('TeenModeService.instance.isLocked'));
    expect(settings, contains('AppRoutes.teenModeSetup'));
    expect(settings, contains('AppRoutes.teenModeVerify'));
    expect(settings, isNot(contains('青少年模式功能开发中')));
  });

  test('setup and verify pages enforce no recovery flow', () {
    final setup = read('lib/modules/settings/teen_mode_setup_page.dart');
    final verify = read('lib/modules/settings/teen_mode_verify_page.dart');

    expect(setup, contains('设置4位数字密码'));
    expect(setup, contains('确认密码'));
    expect(setup, contains('TeenModeService.instance.enable'));
    expect(setup, contains('青少年模式已开启'));

    expect(verify, contains('输入密码解除青少年模式'));
    expect(verify, contains('TeenModeService.instance.verifyAndDisable'));
    expect(verify, contains('密码验证成功'));
    expect(verify, isNot(contains('忘记密码')));
    expect(verify, isNot(contains('找回密码')));
    expect(verify, isNot(contains('重置密码')));
  });
}
