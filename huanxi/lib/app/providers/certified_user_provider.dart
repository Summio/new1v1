import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_logger.dart';

String formatActivePinCooldownMessage(int remainingSeconds) {
  final seconds = remainingSeconds <= 0 ? 1 : remainingSeconds;
  if (seconds < 60) {
    return '置顶太频繁，请 $seconds 秒后再试';
  }
  final roundedMinutes = (seconds / 60).ceil();
  if (roundedMinutes < 60) {
    return '置顶太频繁，请 $roundedMinutes 分钟后再试';
  }
  final hours = roundedMinutes ~/ 60;
  final minutes = roundedMinutes % 60;
  if (minutes == 0) {
    return '置顶太频繁，请 $hours 小时后再试';
  }
  return '置顶太频繁，请 $hours 小时 $minutes 分钟后再试';
}

int _parseRemainingSeconds(dynamic data) {
  if (data is Map<String, dynamic>) {
    final raw = data['remaining_seconds'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  }
  if (data is Map) {
    final raw = data['remaining_seconds'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  }
  return 0;
}

/// 认证用户信息
class CertifiedUserInfo {
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
  final String? certifiedIntro;
  final double? callPrice;
  final bool? isOnline;
  final bool isBusy;
  final bool videoDndEnabled;
  final String availabilityStatus;
  final String availabilityLabel;
  final String? lastActive;
  final String? status;
  final bool isCertifiedUser;
  final int? diamonds;
  final bool blockedByMe;
  final bool blockedMe;
  final bool interactionBlocked;

  const CertifiedUserInfo({
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
    this.certifiedIntro,
    this.callPrice,
    this.isOnline,
    this.isBusy = false,
    this.videoDndEnabled = false,
    String? availabilityStatus,
    String? availabilityLabel,
    this.lastActive,
    this.status,
    this.isCertifiedUser = true,
    this.diamonds,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.interactionBlocked = false,
  }) : availabilityStatus =
           availabilityStatus ?? ((isOnline ?? false) ? 'online' : 'offline'),
       availabilityLabel =
           availabilityLabel ?? ((isOnline ?? false) ? '在线' : '离线');

  factory CertifiedUserInfo.fromJson(Map<String, dynamic> json) {
    final rawAlbum = json['album_photos'];
    final album = rawAlbum is List
        ? rawAlbum
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    final isOnline = json['is_online'] as bool?;
    final rawStatus = (json['availability_status'] as String?)?.trim();
    final fallbackStatus = (isOnline ?? false) ? 'online' : 'offline';
    final availabilityStatus =
        rawStatus == 'online' ||
            rawStatus == 'busy' ||
            rawStatus == 'dnd' ||
            rawStatus == 'offline'
        ? rawStatus!
        : fallbackStatus;
    final rawLabel = (json['availability_label'] as String?)?.trim();
    final availabilityLabel = rawLabel?.isNotEmpty == true
        ? rawLabel!
        : _availabilityLabelForStatus(availabilityStatus);
    return CertifiedUserInfo(
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
      certifiedIntro: (json['intro'] ?? json['certified_intro']) as String?,
      callPrice: (json['call_price'] as num?)?.toDouble(),
      isOnline: isOnline,
      isBusy: json['is_busy'] as bool? ?? availabilityStatus == 'busy',
      videoDndEnabled:
          json['video_dnd_enabled'] as bool? ?? availabilityStatus == 'dnd',
      availabilityStatus: availabilityStatus,
      availabilityLabel: availabilityLabel,
      lastActive: json['last_active'] as String?,
      status: json['status'] as String?,
      isCertifiedUser: json['is_certified_user'] as bool? ?? true,
      diamonds: (json['diamonds'] as num?)?.toInt(),
      blockedByMe: json['blocked_by_me'] as bool? ?? false,
      blockedMe: json['blocked_me'] as bool? ?? false,
      interactionBlocked: json['interaction_blocked'] as bool? ?? false,
    );
  }

  static String _availabilityLabelForStatus(String status) {
    switch (status) {
      case 'online':
        return '在线';
      case 'busy':
        return '忙碌';
      case 'dnd':
        return '勿扰';
      default:
        return '离线';
    }
  }

  CertifiedUserInfo copyWith({
    bool? isOnline,
    bool? isBusy,
    bool? videoDndEnabled,
    String? availabilityStatus,
    String? availabilityLabel,
  }) {
    final nextStatus = availabilityStatus ?? this.availabilityStatus;
    return CertifiedUserInfo(
      id: id,
      userId: userId,
      avatar: avatar,
      coverUrl: coverUrl,
      albumPhotos: albumPhotos,
      username: username,
      gender: gender,
      birthDate: birthDate,
      heightCm: heightCm,
      weightKg: weightKg,
      locationCity: locationCity,
      signature: signature,
      certifiedIntro: certifiedIntro,
      callPrice: callPrice,
      isOnline: isOnline ?? this.isOnline,
      isBusy: isBusy ?? this.isBusy,
      videoDndEnabled: videoDndEnabled ?? this.videoDndEnabled,
      availabilityStatus: nextStatus,
      availabilityLabel:
          availabilityLabel ?? _availabilityLabelForStatus(nextStatus),
      lastActive: lastActive,
      status: status,
      isCertifiedUser: isCertifiedUser,
      diamonds: diamonds,
      blockedByMe: blockedByMe,
      blockedMe: blockedMe,
      interactionBlocked: interactionBlocked,
    );
  }
}

/// 认证用户列表状态
class CertifiedUserListState {
  final List<CertifiedUserInfo> certifiedUsers;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String section;
  final String? error;

  const CertifiedUserListState({
    this.certifiedUsers = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.section = 'recommend',
    this.error,
  });

  CertifiedUserListState copyWith({
    List<CertifiedUserInfo>? certifiedUsers,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? section,
    String? error,
  }) {
    return CertifiedUserListState(
      certifiedUsers: certifiedUsers ?? this.certifiedUsers,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      section: section ?? this.section,
      error: error ?? this.error,
    );
  }
}

/// 认证用户列表 Provider
class CertifiedUserListNotifier extends StateNotifier<CertifiedUserListState> {
  final DioClient _dio;
  int _requestSerial = 0;

  CertifiedUserListNotifier(this._dio) : super(const CertifiedUserListState());

  void setSection(String section) {
    if (state.section == section) return;
    state = CertifiedUserListState(section: section);
    fetchCertifiedUsers(refresh: true);
  }

  /// 获取认证用户列表
  Future<void> fetchCertifiedUsers({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;
    if (!refresh && !state.hasMore) return;

    final requestId = ++_requestSerial;
    final requestSection = state.section;
    final page = refresh ? 1 : state.currentPage;

    state = state.copyWith(
      certifiedUsers: refresh ? const [] : state.certifiedUsers,
      isLoading: true,
      error: null,
    );

    try {
      final data = await _dio.apiGet(
        ApiEndpoints.certifiedUserList,
        params: {'page': page, 'page_size': 20, 'section': requestSection},
      );

      if (requestId != _requestSerial || state.section != requestSection) {
        return;
      }

      final rows = data['rows'] as List<dynamic>? ?? [];
      final hasMore = data['has_more'] as bool? ?? false;

      final newCertifiedUsers = rows.map((e) {
        return CertifiedUserInfo.fromJson(Map<String, dynamic>.from(e));
      }).toList();

      if (refresh) {
        // 后台更新头像但 URL 不变时，主动清理对应缓存，避免首页列表显示旧图
        for (final item in newCertifiedUsers) {
          final cover = item.coverUrl?.trim();
          if (cover == null || cover.isEmpty) continue;
          imageCache.evict(NetworkImage(cover));
        }
      }

      state = state.copyWith(
        certifiedUsers: refresh
            ? newCertifiedUsers
            : [...state.certifiedUsers, ...newCertifiedUsers],
        isLoading: false,
        hasMore: hasMore,
        currentPage: page + 1,
      );
    } catch (e) {
      if (requestId != _requestSerial || state.section != requestSection) {
        return;
      }
      AppLogger.debug('certifiedUser.fetchCertifiedUsers error: $e');
      state = state.copyWith(isLoading: false, error: '认证用户列表加载失败，请稍后重试');
    }
  }

  /// 下拉刷新
  Future<void> refresh() => fetchCertifiedUsers(refresh: true);

  /// 加载更多
  Future<void> loadMore() => fetchCertifiedUsers(refresh: false);

  Future<String?> pinActiveCertifiedUser() async {
    try {
      await _dio.apiPost(ApiEndpoints.certifiedUserActivePin);
      if (state.section == 'active') {
        await fetchCertifiedUsers(refresh: true);
      }
      return null;
    } on ApiException catch (e) {
      if (e.code == 429) {
        final remainingSeconds = _parseRemainingSeconds(e.data);
        if (remainingSeconds > 0) {
          return formatActivePinCooldownMessage(remainingSeconds);
        }
      }
      final message = e.message.trim();
      if (message.isNotEmpty) return message;
      if (e.code == 400) return '当前为勿扰状态，请关闭勿扰后再置顶';
      return '置顶失败，请稍后重试';
    } on NetworkException catch (e) {
      return e.message;
    } catch (e) {
      AppLogger.debug('certifiedUser.pinActiveCertifiedUser error: $e');
      return '置顶失败，请稍后重试';
    }
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
    final nextUsers = state.certifiedUsers
        .map((item) {
          if (item.userId != userId) return item;
          changed = true;
          return item.copyWith(
            isOnline: online,
            isBusy: isBusy,
            videoDndEnabled: videoDndEnabled,
            availabilityStatus: availabilityStatus,
            availabilityLabel: availabilityLabel,
          );
        })
        .toList(growable: false);
    if (!changed) return;
    state = state.copyWith(certifiedUsers: nextUsers);
  }
}

/// 认证用户列表 Provider
final certifiedUserListProvider =
    StateNotifierProvider<CertifiedUserListNotifier, CertifiedUserListState>((
      ref,
    ) {
      return CertifiedUserListNotifier(DioClient.instance);
    });
