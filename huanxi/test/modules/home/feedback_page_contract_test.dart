import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feedback route and api endpoint are registered', () {
    final endpoints = File('lib/core/constants/api_endpoints.dart').readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    final profile = File('lib/modules/home/profile_page.dart').readAsStringSync();
    final page = File('lib/modules/home/feedback_page.dart').readAsStringSync();

    expect(endpoints, contains('feedbackCreate'));
    expect(endpoints, contains('app/feedback/create'));
    expect(router, contains('AppRoutes.feedback'));
    expect(router, contains("'/profile/feedback'"));
    expect(router, contains('FeedbackPage'));
    expect(profile, contains('意见反馈'));
    expect(profile, contains('AppRoutes.feedback'));
    expect(page, contains('提交反馈'));
    expect(page, contains('请输入您的意见反馈'));
    expect(page, contains('maxLength: _maxLength'));
    expect(page, contains('DioClient.instance.apiPost'));
  });
}
