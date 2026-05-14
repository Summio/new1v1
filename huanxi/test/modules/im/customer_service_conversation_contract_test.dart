import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer service conversation skips ordinary profile and billing flows', () {
    final text = File('lib/modules/im/im_page.dart').readAsStringSync();

    expect(text, contains('_matchesCustomerServiceConversation'));
    expect(text, contains('appInitState.customerServiceUserId'));
    expect(text, contains('if (_isCustomerServiceConversation) return;'));
    expect(text, contains('if (!_isCustomerServiceConversation) {'));
    expect(text, contains('_chargeTextMessageIfNeeded'));
  });

  test('customer service conversation disables ordinary interaction actions', () {
    final text = File('lib/modules/im/im_page.dart').readAsStringSync();

    expect(text, contains('客服会话不支持送礼物'));
    expect(text, contains('客服会话不支持视频通话'));
    expect(text, contains('actions: _isCustomerServiceConversation'));
    expect(text, contains('if (!_isCustomerServiceConversation)'));
    expect(text, contains('_openMoreActions'));
  });

  test('messages page uses configured customer service profile for matching conversations', () {
    final text = File('lib/modules/home/messages_page.dart').readAsStringSync();

    expect(text, contains('customerServiceUserId'));
    expect(text, contains('_matchesCustomerServiceConversation'));
    expect(text, contains('customerServiceNickname'));
    expect(text, contains('customerServiceAvatar'));
  });
}
