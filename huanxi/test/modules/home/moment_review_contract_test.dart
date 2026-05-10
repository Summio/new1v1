import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moment service parses review status fields', () {
    final service = File('lib/services/moment_service.dart').readAsStringSync();

    expect(service, contains('final String reviewStatus'));
    expect(service, contains('final String? reviewRemark'));
    expect(service, contains('final String? reviewedAt'));
    expect(service, contains("json['review_status']"));
    expect(service, contains("json['review_remark']"));
  });

  test(
    'publish moment submits for review instead of showing published success',
    () {
      final page = File(
        'lib/modules/home/publish_moment_page.dart',
      ).readAsStringSync();

      expect(page, contains('已提交审核'));
      expect(page, isNot(contains("发布成功'")));
    },
  );

  test('my moments page enables review status display', () {
    final page = File(
      'lib/modules/home/my_moments_page.dart',
    ).readAsStringSync();
    final listView = File(
      'lib/modules/home/moment_list_view.dart',
    ).readAsStringSync();
    final card = File('lib/modules/home/moment_card.dart').readAsStringSync();

    expect(page, contains('showReviewStatus: true'));
    expect(listView, contains('final bool showReviewStatus'));
    expect(card, contains('final bool showReviewStatus'));
    expect(card, contains('待审核'));
    expect(card, contains('已驳回'));
    expect(card, contains('驳回原因'));
  });

  test(
    'moment publish entry checks review status before navigation and render',
    () {
      final myMoments = File(
        'lib/modules/home/my_moments_page.dart',
      ).readAsStringSync();
      final publish = File(
        'lib/modules/home/publish_moment_page.dart',
      ).readAsStringSync();
      final service = File(
        'lib/services/review_entry_guard_service.dart',
      ).readAsStringSync();

      expect(service, contains('reviewEntryStatus'));
      expect(service, contains('reasonCode'));
      expect(myMoments, contains('fetchEntryStatus'));
      expect(myMoments, contains('momentPublish.canEnter'));
      expect(myMoments, contains('状态检查失败，请稍后再试'));
      expect(publish, contains('_isEntryChecking'));
      expect(publish, contains('CircularProgressIndicator'));
      expect(publish, contains('momentPublish.canEnter'));
      expect(publish, contains('AppRoutes.myMoments'));
    },
  );
}
