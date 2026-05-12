import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('certified user detail exposes same more actions as im page', () {
    final detailPage = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();
    final imPage = File('lib/modules/im/im_page.dart').readAsStringSync();
    final moreActions = File(
      'lib/modules/home/user_more_actions.dart',
    ).readAsStringSync();

    expect(detailPage, contains('Icons.more_horiz'));
    expect(detailPage, contains('showUserMoreActions'));
    expect(imPage, contains('showUserMoreActions'));
    expect(detailPage, isNot(contains('UserComplaintScene.profile')));
    expect(detailPage, contains('blockedByMe'));
    expect(detailPage, contains('blockedMe'));
    expect(detailPage, contains('interactionBlocked'));
    expect(detailPage, contains('无法互相关注、聊天、通话和送礼'));

    expect(moreActions, contains('拉黑'));
    expect(moreActions, contains('解除拉黑'));
    expect(moreActions, contains('投诉'));
    expect(moreActions, contains('AppRoutes.userComplaint'));
    expect(moreActions, isNot(contains('_ComplaintDialog')));
  });
}
