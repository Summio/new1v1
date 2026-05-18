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

  test('nickname adjacent VIP badges use compact spacing', () {
    const nicknameBadgeFiles = [
      'lib/modules/im/im_page.dart',
      'lib/modules/home/my_following_page.dart',
      'lib/modules/home/user_search_page.dart',
      'lib/modules/home/moment_card.dart',
      'lib/modules/home/messages_page.dart',
      'lib/modules/home/discover_page.dart',
      'lib/modules/home/home_page.dart',
      'lib/modules/home/flirt_user_list_page.dart',
      'lib/modules/home/call_page.dart',
      'lib/modules/call/call_room_page.dart',
      'lib/modules/call/incoming_call_page.dart',
      'lib/modules/call/call_outgoing_page.dart',
    ];
    final wideSpacingPattern = RegExp(
      r'const SizedBox\(width: (?:[5-9]|[1-9]\d+)\),\s*const VipBadge',
      multiLine: true,
    );

    for (final filePath in nicknameBadgeFiles) {
      final content = File(filePath).readAsStringSync();

      expect(
        wideSpacingPattern.hasMatch(content),
        isFalse,
        reason: '$filePath has more than 4px before nickname VIP badge',
      );
    }
  });

  test(
    'chat detail and relationship lists render VIP badge from loaded user data',
    () {
      final imPage = File('lib/modules/im/im_page.dart').readAsStringSync();
      final followingPage = File(
        'lib/modules/home/my_following_page.dart',
      ).readAsStringSync();

      expect(imPage, contains("import '../../app/widgets/vip_badge.dart';"));
      expect(imPage, contains('_peerIsVip = payload[\'is_vip\'] == true'));
      expect(imPage, contains('if (_peerIsVip) ...['));
      expect(imPage, contains('const VipBadge(dense: true)'));

      expect(
        followingPage,
        contains("import '../../app/widgets/vip_badge.dart';"),
      );
      expect(followingPage, contains('if (user.isVip) ...['));
      expect(followingPage, contains('const VipBadge(dense: true)'));
    },
  );

  test(
    'nickname VIP badges stay adjacent instead of being pushed to row edge',
    () {
      const nicknameBadgeFiles = [
        'lib/modules/home/user_search_page.dart',
        'lib/modules/home/messages_page.dart',
        'lib/modules/home/discover_page.dart',
        'lib/modules/home/home_page.dart',
        'lib/modules/home/my_following_page.dart',
      ];
      final expandedBeforeBadgePattern = RegExp(
        r'Expanded\(\s*child: Text\([\s\S]{0,500}?if \([^)]*isVip[^)]*\) \.\.\.\[',
        multiLine: true,
      );

      for (final filePath in nicknameBadgeFiles) {
        final content = File(filePath).readAsStringSync();

        expect(
          expandedBeforeBadgePattern.hasMatch(content),
          isFalse,
          reason: '$filePath pushes nickname VIP badge away from nickname',
        );
      }
    },
  );

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
