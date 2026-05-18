import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/auth_provider.dart';
import 'package:huanxi/app/theme/app_theme.dart';
import 'package:huanxi/core/network/dio_client.dart';
import 'package:huanxi/modules/profile/vip_page.dart';

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

  testWidgets('VIP page package grid does not overflow on small screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => _StaticAuthNotifier(
              const AuthState(isLoggedIn: true, isVip: false),
            ),
          ),
          appInitProvider.overrideWith(
            (ref) => _StaticAppInitNotifier(
              const AppInitState(
                loaded: true,
                vipPackages: [
                  VipPackage(
                    amount: 1990,
                    durationDays: 30,
                    label: '月卡',
                    tag: '推荐',
                    tagColor: '#D7A84F',
                  ),
                  VipPackage(
                    amount: 5800,
                    durationDays: 90,
                    label: '季卡',
                    tag: '省心',
                    tagColor: '#C7902D',
                  ),
                  VipPackage(
                    amount: 19800,
                    durationDays: 365,
                    label: '年卡',
                    tag: '超值',
                    tagColor: '#B7791F',
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const VipPage()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _StaticAuthNotifier extends AuthNotifier {
  _StaticAuthNotifier(AuthState initialState) : super(DioClient.instance) {
    state = initialState;
  }

  @override
  Future<void> fetchUserInfo() async {}
}

class _StaticAppInitNotifier extends AppInitNotifier {
  _StaticAppInitNotifier(AppInitState initialState)
    : super(DioClient.instance) {
    state = initialState;
  }

  @override
  Future<void> init() async {}
}
