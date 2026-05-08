enum RankingBoard {
  charm('charm', '魅力榜', '钻石'),
  wealth('wealth', '富豪榜', '金币'),
  invite('invite', '邀请榜', '人');

  const RankingBoard(this.value, this.label, this.unit);

  final String value;
  final String label;
  final String unit;
}

enum RankingPeriod {
  day('day', '日榜'),
  week('week', '周榜'),
  month('month', '月榜');

  const RankingPeriod(this.value, this.label);

  final String value;
  final String label;
}

Map<String, dynamic> buildRankingQueryParams({
  required RankingBoard board,
  required RankingPeriod period,
}) {
  return {'board': board.value, 'period': period.value};
}

class RankingItem {
  final int rank;
  final int userId;
  final String nickname;
  final String avatar;
  final double scoreGapFromTop;
  final String scoreGapText;

  const RankingItem({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.scoreGapFromTop,
    required this.scoreGapText,
  });

  factory RankingItem.fromJson(Map<String, dynamic> json) {
    return RankingItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      nickname: (json['nickname'] as String?)?.trim() ?? '',
      avatar: (json['avatar'] as String?)?.trim() ?? '',
      scoreGapFromTop: _toDouble(json['score_gap_from_top']),
      scoreGapText: (json['score_gap_text'] as String?)?.trim() ?? '',
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
