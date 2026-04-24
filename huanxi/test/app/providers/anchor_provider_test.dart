import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/anchor_provider.dart';
import 'package:huanxi/app/providers/user_search_provider.dart';

void main() {
  group('AnchorInfo', () {
    test('parses non-anchor search result flag', () {
      final anchor = AnchorInfo.fromJson({
        'id': 23,
        'user_id': 23,
        'nickname': '小喜',
        'is_anchor': false,
      });

      expect(anchor.userId, 23);
      expect(anchor.username, '小喜');
      expect(anchor.isAnchor, isFalse);
    });

    test('defaults old anchor list rows to anchor users', () {
      final anchor = AnchorInfo.fromJson({
        'id': 8,
        'user_id': 8,
        'nickname': '主播A',
      });

      expect(anchor.isAnchor, isTrue);
    });
  });

  group('user search query params', () {
    test('trims keyword and omits empty keyword', () {
      expect(buildUserSearchQueryParams(page: 2, pageSize: 20, keyword: '  小喜  '), {
        'page': 2,
        'page_size': 20,
        'keyword': '小喜',
      });
    });
  });
}
