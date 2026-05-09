import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/ranking_provider.dart';

void main() {
  group('RankingItem.fromJson', () {
    test('parses gap fields without requiring real score', () {
      final item = RankingItem.fromJson({
        'rank': 2,
        'user_id': 18,
        'nickname': '小喜',
        'avatar': '/avatar.png',
        'score_gap_from_top': '23.5',
        'score_gap_text': '距榜首 23.5 钻石',
      });

      expect(item.rank, 2);
      expect(item.userId, 18);
      expect(item.nickname, '小喜');
      expect(item.avatar, '/avatar.png');
      expect(item.scoreGapFromTop, 23.5);
      expect(item.scoreGapText, '距榜首 23.5 钻石');
    });
  });

  group('ranking query params', () {
    test('only sends board and period from app', () {
      expect(
        buildRankingQueryParams(
          board: RankingBoard.wealth,
          period: RankingPeriod.week,
        ),
        {'board': 'wealth', 'period': 'week'},
      );
    });
  });
}
