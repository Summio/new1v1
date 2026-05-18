import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_logger.dart';

class FlirtUserInfo {
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
  final double coins;
  final bool isCertifiedUser;
  final bool isVip;
  final String? vipExpiresAt;
  final String certificationStatus;
  final double? callPrice;
  final bool? isOnline;
  final bool isBusy;
  final bool videoDndEnabled;
  final String availabilityStatus;
  final String availabilityLabel;
  final bool blockedByMe;
  final bool blockedMe;
  final bool interactionBlocked;

  const FlirtUserInfo({
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
    this.coins = 0,
    this.isCertifiedUser = false,
    this.isVip = false,
    this.vipExpiresAt,
    this.certificationStatus = 'none',
    this.callPrice,
    this.isOnline,
    this.isBusy = false,
    this.videoDndEnabled = false,
    String? availabilityStatus,
    String? availabilityLabel,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.interactionBlocked = false,
  }) : availabilityStatus =
           availabilityStatus ?? ((isOnline ?? false) ? 'online' : 'offline'),
       availabilityLabel =
           availabilityLabel ?? ((isOnline ?? false) ? '在线' : '离线');

  factory FlirtUserInfo.fromJson(Map<String, dynamic> json) {
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
    return FlirtUserInfo(
      id: (json['id'] as num?)?.toInt() ?? (json['user_id'] as num).toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? (json['id'] as num).toInt(),
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
      coins: _asDouble(json['coins']),
      isCertifiedUser: json['is_certified_user'] as bool? ?? false,
      isVip: json['is_vip'] as bool? ?? false,
      vipExpiresAt: json['vip_expires_at'] as String?,
      certificationStatus: json['certification_status'] as String? ?? 'none',
      callPrice: (json['call_price'] as num?)?.toDouble(),
      isOnline: isOnline,
      isBusy: json['is_busy'] as bool? ?? availabilityStatus == 'busy',
      videoDndEnabled:
          json['video_dnd_enabled'] as bool? ?? availabilityStatus == 'dnd',
      availabilityStatus: availabilityStatus,
      availabilityLabel: rawLabel?.isNotEmpty == true
          ? rawLabel!
          : _availabilityLabelForStatus(availabilityStatus),
      blockedByMe:
          json['blocked_by_me'] as bool? ??
          json['is_blocked_by_me'] as bool? ??
          false,
      blockedMe:
          json['blocked_me'] as bool? ??
          json['has_blocked_me'] as bool? ??
          false,
      interactionBlocked: json['interaction_blocked'] as bool? ?? false,
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
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

  FlirtUserInfo copyWith({
    bool? isOnline,
    bool? isBusy,
    bool? videoDndEnabled,
    String? availabilityStatus,
    String? availabilityLabel,
  }) {
    final nextStatus = availabilityStatus ?? this.availabilityStatus;
    return FlirtUserInfo(
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
      coins: coins,
      isCertifiedUser: isCertifiedUser,
      isVip: isVip,
      vipExpiresAt: vipExpiresAt,
      certificationStatus: certificationStatus,
      callPrice: callPrice,
      isOnline: isOnline ?? this.isOnline,
      isBusy: isBusy ?? this.isBusy,
      videoDndEnabled: videoDndEnabled ?? this.videoDndEnabled,
      availabilityStatus: nextStatus,
      availabilityLabel:
          availabilityLabel ?? _availabilityLabelForStatus(nextStatus),
      blockedByMe: blockedByMe,
      blockedMe: blockedMe,
      interactionBlocked: interactionBlocked,
    );
  }
}

class FlirtUserListState {
  final List<FlirtUserInfo> users;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const FlirtUserListState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.error,
  });

  FlirtUserListState copyWith({
    List<FlirtUserInfo>? users,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return FlirtUserListState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

class FlirtGreetQuota {
  final int dailyLimit;
  final int used;
  final int remaining;
  final bool enabled;
  final int cooldownSeconds;

  const FlirtGreetQuota({
    this.dailyLimit = 3,
    this.used = 0,
    this.remaining = 0,
    this.enabled = true,
    this.cooldownSeconds = 0,
  });

  factory FlirtGreetQuota.fromJson(Map<String, dynamic> json) {
    return FlirtGreetQuota(
      dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? 3,
      used: (json['used'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      cooldownSeconds: (json['cooldown_seconds'] as num?)?.toInt() ?? 0,
    );
  }

  bool get canSend => enabled && remaining > 0 && cooldownSeconds <= 0;
}

class FlirtGreetResult {
  final bool started;
  final int targetCount;
  final int sentCount;
  final int failedCount;
  final int textDndFailedCount;
  final int imFailedCount;
  final FlirtGreetQuota quota;

  const FlirtGreetResult({
    this.started = false,
    required this.targetCount,
    required this.sentCount,
    required this.failedCount,
    required this.textDndFailedCount,
    required this.imFailedCount,
    required this.quota,
  });

  factory FlirtGreetResult.fromJson(Map<String, dynamic> json) {
    final quotaRaw = json['quota'];
    return FlirtGreetResult(
      started: json['started'] == true,
      targetCount: (json['target_count'] as num?)?.toInt() ?? 0,
      sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      textDndFailedCount: (json['text_dnd_failed_count'] as num?)?.toInt() ?? 0,
      imFailedCount: (json['im_failed_count'] as num?)?.toInt() ?? 0,
      quota: quotaRaw is Map<String, dynamic>
          ? FlirtGreetQuota.fromJson(quotaRaw)
          : const FlirtGreetQuota(),
    );
  }
}

class FlirtGreetState {
  final FlirtGreetQuota quota;
  final bool isLoadingQuota;
  final bool isSending;
  final String? error;

  const FlirtGreetState({
    this.quota = const FlirtGreetQuota(),
    this.isLoadingQuota = false,
    this.isSending = false,
    this.error,
  });

  FlirtGreetState copyWith({
    FlirtGreetQuota? quota,
    bool? isLoadingQuota,
    bool? isSending,
    String? error,
  }) {
    return FlirtGreetState(
      quota: quota ?? this.quota,
      isLoadingQuota: isLoadingQuota ?? this.isLoadingQuota,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

class FlirtGreetNotifier extends StateNotifier<FlirtGreetState> {
  final DioClient _dio;

  FlirtGreetNotifier(this._dio) : super(const FlirtGreetState());

  Future<void> fetchQuota() async {
    state = state.copyWith(isLoadingQuota: true, error: null);
    try {
      final resp = await _dio.apiGet(ApiEndpoints.flirtGreetQuota);
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        quota: FlirtGreetQuota.fromJson(data),
        isLoadingQuota: false,
        error: null,
      );
    } catch (e) {
      AppLogger.debug('flirtGreet.fetchQuota error: $e');
      state = state.copyWith(isLoadingQuota: false, error: '打招呼额度加载失败');
    }
  }

  Future<FlirtGreetResult> send({required int slotIndex}) async {
    if (state.isSending) {
      throw Exception('正在发送，请稍候');
    }
    state = state.copyWith(isSending: true, error: null);
    try {
      final resp = await _dio.apiPost(
        ApiEndpoints.flirtGreet,
        data: {'slot_index': slotIndex},
      );
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final result = FlirtGreetResult.fromJson(data);
      state = state.copyWith(
        quota: result.quota,
        isSending: false,
        error: null,
      );
      return result;
    } catch (e) {
      AppLogger.debug('flirtGreet.send error: $e');
      state = state.copyWith(isSending: false, error: '打招呼发送失败');
      rethrow;
    }
  }
}

class FlirtUserListNotifier extends StateNotifier<FlirtUserListState> {
  final DioClient _dio;
  int _requestSerial = 0;

  FlirtUserListNotifier(this._dio) : super(const FlirtUserListState());

  Future<void> fetchFlirtUsers({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;
    if (!refresh && !state.hasMore) return;

    final requestId = ++_requestSerial;
    final page = refresh ? 1 : state.currentPage;
    state = state.copyWith(
      users: refresh ? const [] : state.users,
      isLoading: true,
      error: null,
    );

    try {
      final data = await _dio.apiGet(
        ApiEndpoints.flirtUserList,
        params: {'page': page, 'page_size': 20},
      );
      if (requestId != _requestSerial) return;

      final rows = data['rows'] as List<dynamic>? ?? [];
      final hasMore = data['has_more'] as bool? ?? false;
      final newUsers = rows
          .map(
            (item) => FlirtUserInfo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

      state = state.copyWith(
        users: refresh ? newUsers : [...state.users, ...newUsers],
        isLoading: false,
        hasMore: hasMore,
        currentPage: page + 1,
        error: null,
      );
    } catch (e) {
      if (requestId != _requestSerial) return;
      AppLogger.debug('flirtUser.fetchFlirtUsers error: $e');
      state = state.copyWith(isLoading: false, error: '搭讪列表加载失败，请稍后重试');
    }
  }

  Future<void> refresh() => fetchFlirtUsers(refresh: true);

  Future<void> loadMore() => fetchFlirtUsers(refresh: false);

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
    state = state.copyWith(users: nextUsers);
  }
}

final flirtUserListProvider =
    StateNotifierProvider<FlirtUserListNotifier, FlirtUserListState>((ref) {
      return FlirtUserListNotifier(DioClient.instance);
    });

final flirtGreetProvider =
    StateNotifierProvider<FlirtGreetNotifier, FlirtGreetState>((ref) {
      return FlirtGreetNotifier(DioClient.instance);
    });
