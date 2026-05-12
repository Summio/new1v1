import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../services/user_home_service.dart';

const int _followPageSize = 20;
const Object _followStateUnset = Object();

class MyFollowingState {
  final List<FollowingUserItem> users;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final int totalCount;
  final String keyword;
  final String? error;

  const MyFollowingState({
    this.users = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.totalCount = 0,
    this.keyword = '',
    this.error,
  });

  MyFollowingState copyWith({
    List<FollowingUserItem>? users,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    int? totalCount,
    String? keyword,
    Object? error = _followStateUnset,
  }) {
    return MyFollowingState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      keyword: keyword ?? this.keyword,
      error: identical(error, _followStateUnset)
          ? this.error
          : error as String?,
    );
  }
}

class MyFollowingNotifier extends StateNotifier<MyFollowingState> {
  final Future<FollowingUsersPage> Function({
    required int page,
    required int pageSize,
    String keyword,
  })
  _loader;
  final String _loadErrorMessage;
  int _requestSerial = 0;

  MyFollowingNotifier(
    UserHomeService service, {
    Future<FollowingUsersPage> Function({
      required int page,
      required int pageSize,
      String keyword,
    })?
    loader,
    String loadErrorMessage = '关注列表加载失败，请稍后重试',
  }) : _loader = loader ?? service.getFollowingUsers,
       _loadErrorMessage = loadErrorMessage,
       super(const MyFollowingState());

  Future<void> refresh() => _fetch(refresh: true);

  Future<void> search(String keyword) =>
      _fetch(refresh: true, keyword: keyword.trim());

  Future<void> loadMore() => _fetch(refresh: false);

  void removeFollowing(int userId) {
    final nextUsers = state.users
        .where((item) => item.user.userId != userId)
        .toList(growable: false);
    state = state.copyWith(
      users: nextUsers,
      totalCount: state.totalCount > 0 ? state.totalCount - 1 : 0,
      error: null,
    );
  }

  void applyAvailabilityUpdate({
    required int userId,
    required bool online,
    required bool isBusy,
    required bool videoDndEnabled,
    required String availabilityStatus,
    required String availabilityLabel,
  }) {
    var changed = false;
    final nextUsers = state.users
        .map((item) {
          if (item.user.userId != userId) return item;
          changed = true;
          return FollowingUserItem(
            user: item.user.copyWith(
              isOnline: online,
              isBusy: isBusy,
              videoDndEnabled: videoDndEnabled,
              availabilityStatus: availabilityStatus,
              availabilityLabel: availabilityLabel,
            ),
            followedAt: item.followedAt,
            blockedAt: item.blockedAt,
          );
        })
        .toList(growable: false);
    if (!changed) return;
    state = state.copyWith(users: nextUsers, error: null);
  }

  Future<void> _fetch({required bool refresh, String? keyword}) async {
    if (state.isLoading || state.isLoadingMore) return;
    if (!refresh && !state.hasMore) return;

    final requestId = ++_requestSerial;
    final requestKeyword = keyword ?? state.keyword;
    final page = refresh ? 1 : state.currentPage;

    state = state.copyWith(
      users: refresh ? const [] : null,
      isLoading: refresh,
      isLoadingMore: !refresh,
      hasMore: refresh ? false : null,
      currentPage: refresh ? 1 : null,
      keyword: requestKeyword,
      error: null,
    );

    try {
      final result = await _loader(
        page: page,
        pageSize: _followPageSize,
        keyword: requestKeyword,
      );
      if (requestId != _requestSerial) return;

      final users = refresh ? result.items : [...state.users, ...result.items];
      state = state.copyWith(
        users: users,
        isLoading: false,
        isLoadingMore: false,
        hasMore: result.hasMore,
        currentPage: page + 1,
        totalCount: result.total,
        keyword: requestKeyword,
        error: null,
      );
    } catch (e) {
      if (requestId != _requestSerial) return;
      AppLogger.debug('myFollowing.load error: $e');
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: _loadErrorMessage,
      );
    }
  }
}

final myFollowingProvider =
    StateNotifierProvider.autoDispose<MyFollowingNotifier, MyFollowingState>((
      ref,
    ) {
      return MyFollowingNotifier(UserHomeService.instance);
    });

final myFansProvider =
    StateNotifierProvider.autoDispose<MyFollowingNotifier, MyFollowingState>((
      ref,
    ) {
      final service = UserHomeService.instance;
      return MyFollowingNotifier(
        service,
        loader: service.getFansUsers,
        loadErrorMessage: '粉丝列表加载失败，请稍后重试',
      );
    });

final myBlacklistProvider =
    StateNotifierProvider.autoDispose<MyFollowingNotifier, MyFollowingState>((
      ref,
    ) {
      final service = UserHomeService.instance;
      return MyFollowingNotifier(
        service,
        loader: service.getBlockedUsers,
        loadErrorMessage: '黑名单加载失败，请稍后重试',
      );
    });
