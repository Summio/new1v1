import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/certified_user_provider.dart';
import 'package:huanxi/app/providers/user_search_provider.dart';

void main() {
  group('CertifiedUserInfo', () {
    test('parses non-certified user search result flag', () {
      final certifiedUser = CertifiedUserInfo.fromJson({
        'id': 23,
        'user_id': 23,
        'nickname': '小喜',
        'is_certified_user': false,
      });

      expect(certifiedUser.userId, 23);
      expect(certifiedUser.username, '小喜');
      expect(certifiedUser.isCertifiedUser, isFalse);
    });

    test('defaults certified user list rows to certified users', () {
      final certifiedUser = CertifiedUserInfo.fromJson({
        'id': 8,
        'user_id': 8,
        'nickname': '认证用户A',
      });

      expect(certifiedUser.isCertifiedUser, isTrue);
    });

    test('parses diamonds balance from certified user list row', () {
      final certifiedUser = CertifiedUserInfo.fromJson({
        'id': 8,
        'user_id': 8,
        'nickname': '认证用户A',
        'diamonds': 3600,
      });

      expect(certifiedUser.diamonds, 3600);
    });
  });

  group('user search query params', () {
    test('trims keyword and omits empty keyword', () {
      expect(
        buildUserSearchQueryParams(page: 2, pageSize: 20, keyword: '  小喜  '),
        {'page': 2, 'page_size': 20, 'keyword': '小喜'},
      );
    });
  });
}



