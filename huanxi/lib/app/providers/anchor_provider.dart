import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/utils/app_logger.dart';

/// 主播信息
class AnchorInfo {
  final int id;
  final int userId;
  final String? avatar;
  final String? username;
  final String? gender;
  final String? anchorIntro;
  final double? callPrice;
  final bool? isOnline;
  final String? lastActive;
  final bool isAnchor;

  const AnchorInfo({
    required this.id,
    required this.userId,
    this.avatar,
    this.username,
    this.gender,
    this.anchorIntro,
    this.callPrice,
    this.isOnline,
    this.lastActive,
    this.isAnchor = true,
  });

  factory AnchorInfo.fromJson(Map<String, dynamic> json) {
    return AnchorInfo(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      avatar: (json['avatar'] as String?)?.trim(),
      username: (json['nickname'] ?? json['username']) as String?,
      gender: json['gender'] as String?,
      anchorIntro: (json['intro'] ?? json['anchor_intro']) as String?,
      callPrice: (json['call_price'] as num?)?.toDouble(),
      isOnline: json['is_online'] as bool?,
      lastActive: json['last_active'] as String?,
      isAnchor: json['is_anchor'] as bool? ?? true,
    );
  }
}

/// 主播列表状态
class AnchorListState {
  final List<AnchorInfo> anchors;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const AnchorListState({
    this.anchors = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  AnchorListState copyWith({
    List<AnchorInfo>? anchors,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return AnchorListState(
      anchors: anchors ?? this.anchors,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error ?? this.error,
    );
  }
}

/// 主播列表 Provider
class AnchorListNotifier extends StateNotifier<AnchorListState> {
  final DioClient _dio;

  AnchorListNotifier(this._dio) : super(const AnchorListState());

  /// 获取主播列表
  Future<void> fetchAnchors({bool refresh = false}) async {
    if (state.isLoading) return;
    if (!refresh && !state.hasMore) return;

    state = state.copyWith(isLoading: true, error: null);

    final page = refresh ? 1 : state.currentPage;

    try {
      final data = await _dio.apiGet(
        ApiEndpoints.anchorList,
        params: {'page': page, 'page_size': 20},
      );

      final rows = data['rows'] as List<dynamic>? ?? [];
      final hasMore = data['has_more'] as bool? ?? false;

      final newAnchors = rows.map((e) {
        return AnchorInfo.fromJson(Map<String, dynamic>.from(e));
      }).toList();

      if (refresh) {
        // 后台更新头像但 URL 不变时，主动清理对应缓存，避免首页列表显示旧图
        for (final item in newAnchors) {
          final avatar = item.avatar?.trim();
          if (avatar == null || avatar.isEmpty) continue;
          imageCache.evict(NetworkImage(avatar));
        }
      }

      state = state.copyWith(
        anchors: refresh ? newAnchors : [...state.anchors, ...newAnchors],
        isLoading: false,
        hasMore: hasMore,
        currentPage: page + 1,
      );
    } catch (e) {
      AppLogger.debug('anchor.fetchAnchors error: $e');
      state = state.copyWith(isLoading: false, error: '主播列表加载失败，请稍后重试');
    }
  }

  /// 下拉刷新
  Future<void> refresh() => fetchAnchors(refresh: true);

  /// 加载更多
  Future<void> loadMore() => fetchAnchors(refresh: false);
}

/// 主播列表 Provider
final anchorListProvider =
    StateNotifierProvider<AnchorListNotifier, AnchorListState>((ref) {
      return AnchorListNotifier(DioClient.instance);
    });
