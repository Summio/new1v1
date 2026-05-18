import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile page exposes VIP entry and badge', () {
    final profile = File(
      'lib/modules/home/profile_page.dart',
    ).readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();

    expect(profile, contains('VIP会员'));
    expect(profile, contains('VipBadge'));
    expect(profile, contains('AppRoutes.vip'));
    expect(router, contains("static const String vip = '/profile/vip'"));
  });

  test('VIP purchase page displays cent amount as yuan', () {
    final page = File('lib/modules/profile/vip_page.dart').readAsStringSync();
    final provider = File(
      'lib/app/providers/auth_provider.dart',
    ).readAsStringSync();

    expect(page, contains('amount'));
    expect(page, contains('amountYuan'));
    expect(page, contains('ApiEndpoints.vipOrderCreate'));
    expect(page, contains('暂无可购买套餐'));
    expect(provider, contains('/ 100'));
  });

  test('shared VIP badge component exists', () {
    final badge = File('lib/app/widgets/vip_badge.dart').readAsStringSync();

    expect(badge, contains('class VipBadge'));
    expect(badge, contains('VIP'));
  });
}
