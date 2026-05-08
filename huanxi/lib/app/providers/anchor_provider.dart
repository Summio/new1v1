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
  final String? coverUrl;
  final List<String> albumPhotos;
  final String? username;
  final String? gender;
  final String? birthDate;
  final int? heightCm;
  final int? weightKg;
  final String? locationCity;
  final String? signature;
  final String? anchorIntro;
  final double? callPrice;
  final bool? isOnline;
  final String? lastActive;
  final String? status;
  final bool isAnchor;
  final int? diamonds;

  const AnchorInfo({
    required this.id,
    required this.userId,
    this.avatar,
    this.coverUrl,
    this.albumPhotos = const [],
    this.username,
    this.gender,
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.locationCity,
    this.signature,
    this.anchorIntro,
    this.callPrice,
    this.isOnline,
    this.lastActive,
    this.status,
    this.isAnchor = true,
    this.diamonds,
  });

  factory AnchorInfo.fromJson(Map<String, dynamic> json) {
    final rawAlbum = json['album_photos'];
    final album = rawAlbum is List
        ? rawAlbum
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    return AnchorInfo(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      avatar: (json['avatar'] as String?)?.trim(),
      coverUrl: (json['cover_url'] as String?)?.trim(),
      albumPhotos: album,
      username: (json['nickname'] ?? json['username']) as String?,
      gender: json['gender'] as String?,
      birthDate: json['birth_date'] as String?,
      heightCm: (json['height_cm'] as num?)?.toInt(),
      weightKg: (json['weight_kg'] as num?)?.toInt(),
      locationCity: json['location_city'] as String?,
      signature: (json['signature'] as String?)?.trim(),
      anchorIntro: (json['intro'] ?? json['anchor_intro']) as String?,
      callPrice: (json['call_price'] as num?)?.toDouble(),
      isOnline: json['is_online'] as bool?,
      lastActive: json['last_active'] as String?,
      status: json['status'] as String?,
      isAnchor: json['is_anchor'] as bool? ?? true,
      diamonds: (json['diamonds'] as num?)?.toInt(),
    );
  }
}

/// 主播列表状态
class AnchorListState {
  final List<AnchorInfo> anchors;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String section;
  final String? error;

  const AnchorListState({
    this.anchors = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.section = 'recommend',
    this.error,
  });

  AnchorListState copyWith({
    List<AnchorInfo>? anchors,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? section,
    String? error,
  }) {
    return AnchorListState(
      anchors: anchors ?? this.anchors,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      section: section ?? this.section,
      error: error ?? this.error,
    );
  }
}

/// 主播列表 Provider
class AnchorListNotifier extends StateNotifier<AnchorListState> {
  final DioClient _dio;
  int _requestSerial = 0;

  AnchorListNotifier(this._dio) : super(const AnchorListState());

  void setSection(String section) {
    if (state.section == section) return;
    state = AnchorListState(section: section);
    fetchAnchors(refresh: true);
  }

  /// 获取主播列表
  Future<void> fetchAnchors({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;
    if (!refresh && !state.hasMore) return;

    final requestId = ++_requestSerial;
    final requestSection = state.section;
    final page = refresh ? 1 : state.currentPage;

    state = state.copyWith(
      anchors: refresh ? const [] : state.anchors,
      isLoading: true,
      error: null,
    );

    try {
      final data = await _dio.apiGet(
        ApiEndpoints.anchorList,
        params: {'page': page, 'page_size': 20, 'section': requestSection},
      );

      if (requestId != _requestSerial || state.section != requestSection) {
        return;
      }

      final rows = data['rows'] as List<dynamic>? ?? [];
      final hasMore = data['has_more'] as bool? ?? false;

      final newAnchors = rows.map((e) {
        return AnchorInfo.fromJson(Map<String, dynamic>.from(e));
      }).toList();

      if (refresh) {
        // 后台更新头像但 URL 不变时，主动清理对应缓存，避免首页列表显示旧图
        for (final item in newAnchors) {
          final cover = item.coverUrl?.trim();
          if (cover == null || cover.isEmpty) continue;
          imageCache.evict(NetworkImage(cover));
        }
      }

      state = state.copyWith(
        anchors: refresh ? newAnchors : [...state.anchors, ...newAnchors],
        isLoading: false,
        hasMore: hasMore,
        currentPage: page + 1,
      );
    } catch (e) {
      if (requestId != _requestSerial || state.section != requestSection) {
        return;
      }
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
