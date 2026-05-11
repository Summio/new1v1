import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/ranking_models.dart';

void main() {
  test('RankingItem parses anonymous rows without exposing user id', () {
    final item = RankingItem.fromJson({
      'rank': 1,
      'user_id': null,
      'nickname': '神秘人',
      'avatar': '',
      'is_anonymous': true,
      'score_gap_from_top': 0,
      'score_gap_text': '距榜首 0 钻石',
    });

    expect(item.rank, 1);
    expect(item.userId, isNull);
    expect(item.nickname, '神秘人');
    expect(item.avatar, '');
    expect(item.isAnonymous, isTrue);
  });

  test('RankingItem keeps normal rows navigable', () {
    final item = RankingItem.fromJson({
      'rank': 2,
      'user_id': 11,
      'nickname': '第二名',
      'avatar': '/b.png',
      'is_anonymous': false,
      'score_gap_from_top': 20,
      'score_gap_text': '距榜首 20 钻石',
    });

    expect(item.userId, 11);
    expect(item.isAnonymous, isFalse);
  });
}
