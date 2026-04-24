import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_logger.dart';
import 'anchor_provider.dart';

Map<String, dynamic> buildUserSearchQueryParams({
  required int page,
  required int pageSize,
  required String keyword,
}) {
  return {
    'page': page,
    'page_size': pageSize,
    'keyword': keyword.trim(),
  };
}

class UserSearchState {
  final List<AnchorInfo> users;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String keyword;
  final String? error;

  const UserSearchState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = false,
    this.currentPage = 1,
    this.keyword = '',
    this.error,
  });

  UserSearchState copyWith({
    List<AnchorInfo>? users,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? keyword,
    String? error,
  }) {
    return UserSearchState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      keyword: keyword ?? this.keyword,
      error: error,
    );
  }

  bool get hasKeyword => keyword.trim().isNotEmpty;
}

class UserSearchNotifier extends StateNotifier<UserSearchState> {
  final DioClient _dio;

  UserSearchNotifier(this._dio) : super(const UserSearchState());

  Future<void> search(String keyword) async {
    final trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) {
      state = const UserSearchState();
      return;
    }
    await _fetch(keyword: trimmedKeyword, refresh: true);
  }

  Future<void> loadMore() async {
    if (!state.hasKeyword) return;
    await _fetch(keyword: state.keyword, refresh: false);
  }

  Future<void> _fetch({required String keyword, required bool refresh}) async {
    if (state.isLoading) return;
    if (!refresh && !state.hasMore) return;

    final page = refresh ? 1 : state.currentPage;
    state = state.copyWith(
      users: refresh ? const [] : null,
      isLoading: true,
      hasMore: refresh ? false : null,
      currentPage: refresh ? 1 : null,
      keyword: keyword,
      error: null,
    );

    try {
      final data = await _dio.apiGet(
        ApiEndpoints.anchorList,
        params: buildUserSearchQueryParams(
          page: page,
          pageSize: 20,
          keyword: keyword,
        ),
      );
      final rows = data['rows'] as List<dynamic>? ?? [];
      final newUsers = rows
          .map((e) => AnchorInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      state = state.copyWith(
        users: refresh ? newUsers : [...state.users, ...newUsers],
        isLoading: false,
        hasMore: data['has_more'] as bool? ?? false,
        currentPage: page + 1,
        keyword: keyword,
        error: null,
      );
    } catch (e) {
      AppLogger.debug('userSearch.search error: $e');
      state = state.copyWith(
        isLoading: false,
        keyword: keyword,
        error: '搜索失败，请稍后重试',
      );
    }
  }
}

final userSearchProvider =
    StateNotifierProvider.autoDispose<UserSearchNotifier, UserSearchState>((ref) {
  return UserSearchNotifier(DioClient.instance);
});
