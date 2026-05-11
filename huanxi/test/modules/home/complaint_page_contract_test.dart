import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complaint page is an independent page with target user info', () {
    final page = File(
      'lib/modules/home/complaint_page.dart',
    ).readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();

    expect(page, contains('class ComplaintPage'));
    expect(router, contains('AppRoutes.userComplaint'));
    expect(router, contains('ComplaintPage'));

    expect(page, contains('投诉用户'));
    expect(page, contains('被投诉人ID'));
    expect(page, contains('被投诉人昵称'));
    expect(page, contains('投诉参数无效，请返回重试'));
    expect(page, contains('骚扰辱骂'));
    expect(page, contains('色情低俗'));
    expect(page, contains('诈骗引流'));
    expect(page, contains('虚假资料'));
    expect(page, contains('其他'));
    expect(page, contains('maxLength: 1000'));
    expect(page, contains('createComplaint'));
    expect(page, contains('投诉已提交'));
    expect(page, contains('context.pop'));
  });
}
