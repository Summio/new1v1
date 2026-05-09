import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ranking_service.dart';
import 'ranking_models.dart';

export 'ranking_models.dart';

class RankingState {
  final RankingBoard board;
  final RankingPeriod period;
  final List<RankingItem> rows;
  final bool isLoading;
  final String? error;
  final int appDisplayLimit;
  final String scoreUnit;

  const RankingState({
    this.board = RankingBoard.charm,
    this.period = RankingPeriod.day,
    this.rows = const [],
    this.isLoading = false,
    this.error,
    this.appDisplayLimit = 20,
    this.scoreUnit = '钻石',
  });

  RankingState copyWith({
    RankingBoard? board,
    RankingPeriod? period,
    List<RankingItem>? rows,
    bool? isLoading,
    String? error,
    int? appDisplayLimit,
    String? scoreUnit,
  }) {
    return RankingState(
      board: board ?? this.board,
      period: period ?? this.period,
      rows: rows ?? this.rows,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      appDisplayLimit: appDisplayLimit ?? this.appDisplayLimit,
      scoreUnit: scoreUnit ?? this.scoreUnit,
    );
  }
}

class RankingNotifier extends StateNotifier<RankingState> {
  RankingNotifier() : super(const RankingState());

  final RankingService _service = RankingService.instance;
  int _requestSerial = 0;

  Future<void> load() async {
    final requestId = ++_requestSerial;
    final board = state.board;
    final period = state.period;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.getRanking(board: board, period: period);
      if (requestId != _requestSerial ||
          state.board != board ||
          state.period != period) {
        return;
      }
      state = state.copyWith(
        rows: result.rows,
        isLoading: false,
        error: null,
        appDisplayLimit: result.appDisplayLimit,
        scoreUnit: result.scoreUnit,
      );
    } catch (e) {
      if (requestId != _requestSerial ||
          state.board != board ||
          state.period != period) {
        return;
      }
      state = state.copyWith(isLoading: false, error: '排行榜加载失败，请稍后重试');
    }
  }

  Future<void> refresh() => load();

  void setBoard(RankingBoard board) {
    if (state.board == board) return;
    state = RankingState(
      board: board,
      period: state.period,
      scoreUnit: board.unit,
    );
    load();
  }

  void setPeriod(RankingPeriod period) {
    if (state.period == period) return;
    state = RankingState(
      board: state.board,
      period: period,
      scoreUnit: state.scoreUnit,
    );
    load();
  }
}

final rankingProvider = StateNotifierProvider<RankingNotifier, RankingState>((
  ref,
) {
  return RankingNotifier();
});
