import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('im page uses shared user more actions for block and complaint', () {
    final imPage = File('lib/modules/im/im_page.dart').readAsStringSync();
    final moreActions = File(
      'lib/modules/home/user_more_actions.dart',
    ).readAsStringSync();
    final endpoints = File(
      'lib/core/constants/api_endpoints.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/user_home_service.dart',
    ).readAsStringSync();

    expect(imPage, isNot(contains('拉黑功能开发中')));
    expect(imPage, isNot(contains('投诉功能开发中')));
    expect(imPage, contains('showUserMoreActions'));
    expect(imPage, contains('_interactionBlocked'));
    expect(imPage, contains('你们之间已存在黑名单关系'));
    expect(imPage, contains('scene: UserComplaintScene.chat'));

    expect(moreActions, isNot(contains('_ComplaintDialog')));
    expect(
      moreActions,
      isNot(contains('builder: (dialogContext) => _ComplaintDialog')),
    );
    expect(moreActions, contains('AppRoutes.userComplaint'));
    expect(moreActions, contains('parentContext.push'));
    expect(moreActions, contains('确认拉黑用户'));
    expect(moreActions, contains('无法互相关注、聊天、通话和送礼'));
    expect(moreActions, contains('投诉用户'));
    expect(moreActions, contains('解除拉黑'));

    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    expect(router, contains('userComplaint'));
    expect(router, contains('ComplaintPage'));

    expect(endpoints, contains('userBlock'));
    expect(endpoints, contains('app/user/block'));
    expect(endpoints, contains('userBlockStatus'));
    expect(endpoints, contains('app/user/block/status'));
    expect(endpoints, contains('complaintCreate'));
    expect(endpoints, contains('app/complaint/create'));

    expect(service, contains('blockUser'));
    expect(service, contains('unblockUser'));
    expect(service, contains('getUserBlockStatus'));
    expect(service, contains('createComplaint'));
  });
}
