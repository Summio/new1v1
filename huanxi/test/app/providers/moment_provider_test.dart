import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/moment_provider.dart';
import 'package:huanxi/services/moment_service.dart';

void main() {
  group('Moment', () {
    test('parses operation flags from feed rows', () {
      final moment = Moment.fromJson({
        'id': 1,
        'user_id': 2,
        'content': 'hello',
        'is_pinned': true,
        'pinned_at': '2026-05-08T12:00:00',
        'is_recommended': true,
        'recommend_override': false,
        'author_is_certified_user': true,
        'author_is_recommended': true,
      });

      expect(moment.isPinned, isTrue);
      expect(moment.pinnedAt, '2026-05-08T12:00:00');
      expect(moment.isRecommended, isTrue);
      expect(moment.recommendOverride, isFalse);
      expect(moment.authorIsCertifiedUser, isTrue);
      expect(moment.authorIsRecommended, isTrue);
    });

    test('keeps old feed rows compatible when operation flags are absent', () {
      final moment = Moment.fromJson({
        'id': 1,
        'user_id': 2,
        'content': 'hello',
      });

      expect(moment.isPinned, isFalse);
      expect(moment.pinnedAt, isNull);
      expect(moment.isRecommended, isFalse);
      expect(moment.recommendOverride, isNull);
      expect(moment.authorIsCertifiedUser, isFalse);
      expect(moment.authorIsRecommended, isFalse);
    });
  });

  group('MomentFeedCategory', () {
    test('uses backend category values', () {
      expect(MomentFeedCategory.recommend.apiValue, 'recommend');
      expect(MomentFeedCategory.latest.apiValue, 'latest');
      expect(MomentFeedCategory.following.apiValue, 'following');
    });
  });
}
