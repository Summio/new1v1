import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile exposes my fans entry and route', () {
    final profilePage = File(
      'lib/modules/home/profile_page.dart',
    ).readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();

    expect(profilePage, contains('我的粉丝'));
    expect(profilePage, contains('AppRoutes.myFans'));
    expect(router, contains('static const String myFans'));
    expect(router, contains('MyFansPage'));
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
    final anchorDetailPage = File(
      'lib/modules/home/anchor_detail_page.dart',
    ).readAsStringSync();

    expect(followingPage, contains('确认取消关注'));
    expect(followingPage, contains('确定不再关注'));
    expect(anchorDetailPage, contains('确认取消关注'));
    expect(anchorDetailPage, contains('确定不再关注'));
  });
}
