import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/moment_service.dart';
import '../../app/providers/auth_provider.dart';

/// 动态列表状态
class MomentListState {
  final List<Moment> moments;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  const MomentListState({
    this.moments = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  MomentListState copyWith({
    List<Moment>? moments,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return MomentListState(
      moments: moments ?? this.moments,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// 全局动态列表 Notifier
class MomentFeedNotifier extends StateNotifier<MomentListState> {
  MomentFeedNotifier() : super(const MomentListState());

  final MomentService _service = MomentService.instance;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.getFeed(page: 1, pageSize: 20);
      state = state.copyWith(
        moments: result.rows,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = (state.moments.length ~/ 20) + 1;
      final result = await _service.getFeed(page: page, pageSize: 20);
      state = state.copyWith(
        moments: [...state.moments, ...result.rows],
        isLoadingMore: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void addMoment(Moment moment) {
    state = state.copyWith(moments: [moment, ...state.moments]);
  }

  void removeMoment(int momentId) {
    state = state.copyWith(
      moments: state.moments.where((m) => m.id != momentId).toList(),
    );
  }
}

/// 我的动态列表 Notifier
class MyMomentsNotifier extends StateNotifier<MomentListState> {
  MyMomentsNotifier() : super(const MomentListState());

  final MomentService _service = MomentService.instance;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.getMyMoments(page: 1, pageSize: 20);
      state = state.copyWith(
        moments: result.rows,
        isLoading: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = (state.moments.length ~/ 20) + 1;
      final result = await _service.getMyMoments(page: page, pageSize: 20);
      state = state.copyWith(
        moments: [...state.moments, ...result.rows],
        isLoadingMore: false,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void addMoment(Moment moment) {
    state = state.copyWith(moments: [moment, ...state.moments]);
  }

  void removeMoment(int momentId) {
    state = state.copyWith(
      moments: state.moments.where((m) => m.id != momentId).toList(),
    );
  }

  Future<bool> deleteMoment(int momentId) async {
    try {
      await _service.deleteMoment(momentId);
      removeMoment(momentId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Provider
final momentFeedProvider = StateNotifierProvider<MomentFeedNotifier, MomentListState>((ref) {
  final notifier = MomentFeedNotifier();
  return notifier;
});

final myMomentsProvider = StateNotifierProvider<MyMomentsNotifier, MomentListState>((ref) {
  final notifier = MyMomentsNotifier();
  return notifier;
});