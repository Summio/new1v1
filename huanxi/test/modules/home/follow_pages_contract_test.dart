import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat route exposes conversation call and relation tabs', () {
    final chatPageFile = File('lib/modules/home/chat_page.dart');
    expect(chatPageFile.existsSync(), isTrue);

    final chatPage = chatPageFile.readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    final mainShell = File(
      'lib/modules/home/main_shell.dart',
    ).readAsStringSync();

    expect(mainShell, contains("label: '聊天'"));
    expect(router, contains('ChatPage'));
    expect(chatPage, contains('_ChatCategorySegment'));
    expect(chatPage, contains("const ['消息', '通话', '关系']"));
    expect(chatPage, contains("const ['关注', '粉丝', '黑名单']"));
    expect(chatPage, contains('TabBarView'));
  });

  test('profile moves call and relation entries into chat page', () {
    final profilePage = File(
      'lib/modules/home/profile_page.dart',
    ).readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    final chatPage = File('lib/modules/home/chat_page.dart').readAsStringSync();

    expect(profilePage, isNot(contains('AppRoutes.callHistory')));
    expect(profilePage, isNot(contains('AppRoutes.myFollowing')));
    expect(profilePage, isNot(contains('AppRoutes.myFans')));
    expect(chatPage, contains('MyFollowingPage.embedded'));
    expect(chatPage, contains('MyFansPage.embedded'));
    expect(router, contains('static const String myFans'));
    expect(router, contains('MyFansPage'));
  });

  test(
    'profile keeps coin balance recharge but removes recharge menu item',
    () {
      final profilePage = File(
        'lib/modules/home/profile_page.dart',
      ).readAsStringSync();

      expect(profilePage, contains('context.push(AppRoutes.recharge)'));
      expect(profilePage, isNot(contains("title: '充值'")));
    },
  );

  test('settings does not expose blacklist entry', () {
    final settingsPage = File(
      'lib/modules/settings/settings_page.dart',
    ).readAsStringSync();

    expect(settingsPage, isNot(contains('黑名单管理')));
    expect(
      settingsPage,
      isNot(contains('/messages?tab=relations&relation=blacklist')),
    );
  });

  test('fan list endpoint is wired in Flutter service', () {
    final endpoints = File(
      'lib/core/constants/api_endpoints.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/user_home_service.dart',
    ).readAsStringSync();

    expect(endpoints, contains('userFansList'));
    expect(endpoints, contains('app/user/fans/list'));
    expect(service, contains('getFansUsers'));
    expect(service, contains('ApiEndpoints.userFansList'));
  });

  test('unfollow action asks for confirmation before request', () {
    final followingPage = File(
      'lib/modules/home/my_following_page.dart',
    ).readAsStringSync();
    final certifiedUserDetailPage = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(followingPage, contains('确认取消关注'));
    expect(followingPage, contains('确定不再关注'));
    expect(certifiedUserDetailPage, contains('确认取消关注'));
    expect(certifiedUserDetailPage, contains('确定不再关注'));
  });
}
