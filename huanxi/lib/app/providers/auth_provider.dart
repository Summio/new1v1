import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/media/image_upload_preprocessor.dart';
import '../../core/storage/storage.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/media_payload_normalizer.dart';
import '../../core/utils/app_logger.dart';
import '../../services/websocket_service.dart';

/// 认证状态
class AuthState {
  final bool isLoggedIn;
  final int? userId;
  final String? username;
  final String? avatar;
  final String? signature;
  final String gender;
  final String? birthDate;
  final int? heightCm;
  final int? weightKg;
  final String? locationCity;
  final List<String> albumPhotos;
  final String? coverUrl;
  final bool isCertifiedUser;
  final String certificationStatus;
  final int certifiedCallPrice;
  final double coins;
  final double diamonds;
  final Map<String, dynamic>? lastProfileUpdateData;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.userId,
    this.username,
    this.avatar,
    this.signature,
    this.gender = 'male',
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.locationCity,
    this.albumPhotos = const [],
    this.coverUrl,
    this.isCertifiedUser = false,
    this.certificationStatus = 'none',
    this.certifiedCallPrice = 0,
    this.coins = 0,
    this.diamonds = 0,
    this.lastProfileUpdateData,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    int? userId,
    String? username,
    String? avatar,
    String? signature,
    String? gender,
    String? birthDate,
    int? heightCm,
    int? weightKg,
    String? locationCity,
    List<String>? albumPhotos,
    String? coverUrl,
    bool? isCertifiedUser,
    String? certificationStatus,
    int? certifiedCallPrice,
    double? coins,
    double? diamonds,
    Map<String, dynamic>? lastProfileUpdateData,
    bool clearLastProfileUpdateData = false,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      signature: signature ?? this.signature,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      locationCity: locationCity ?? this.locationCity,
      albumPhotos: albumPhotos ?? this.albumPhotos,
      coverUrl: coverUrl ?? this.coverUrl,
      isCertifiedUser: isCertifiedUser ?? this.isCertifiedUser,
      certificationStatus: certificationStatus ?? this.certificationStatus,
      certifiedCallPrice: certifiedCallPrice ?? this.certifiedCallPrice,
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
      lastProfileUpdateData: clearLastProfileUpdateData
          ? null
          : lastProfileUpdateData ?? this.lastProfileUpdateData,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// 代币名称状态（coin_name, diamond_name）
class TokenNamesState {
  final String coinName;
  final String diamondName;

  const TokenNamesState({this.coinName = '金币', this.diamondName = '钻石'});

  TokenNamesState copyWith({String? coinName, String? diamondName}) {
    return TokenNamesState(
      coinName: coinName ?? this.coinName,
      diamondName: diamondName ?? this.diamondName,
    );
  }
}

/// 用户能力限制状态
class CapabilityLimitsState {
  final bool certificationMaleOnlyEnabled;
  final bool certificationFemaleOnlyEnabled;
  final bool profileEditCertifiedOnlyEnabled;
  final bool momentPublishCertifiedOnlyEnabled;

  const CapabilityLimitsState({
    this.certificationMaleOnlyEnabled = false,
    this.certificationFemaleOnlyEnabled = false,
    this.profileEditCertifiedOnlyEnabled = false,
    this.momentPublishCertifiedOnlyEnabled = false,
  });

  CapabilityLimitsState copyWith({
    bool? certificationMaleOnlyEnabled,
    bool? certificationFemaleOnlyEnabled,
    bool? profileEditCertifiedOnlyEnabled,
    bool? momentPublishCertifiedOnlyEnabled,
  }) {
    return CapabilityLimitsState(
      certificationMaleOnlyEnabled:
          certificationMaleOnlyEnabled ?? this.certificationMaleOnlyEnabled,
      certificationFemaleOnlyEnabled:
          certificationFemaleOnlyEnabled ?? this.certificationFemaleOnlyEnabled,
      profileEditCertifiedOnlyEnabled:
          profileEditCertifiedOnlyEnabled ??
          this.profileEditCertifiedOnlyEnabled,
      momentPublishCertifiedOnlyEnabled:
          momentPublishCertifiedOnlyEnabled ??
          this.momentPublishCertifiedOnlyEnabled,
    );
  }

  static CapabilityLimitsState fromBootstrapMap(
    Map<String, dynamic>? respData,
  ) {
    final capabilityLimits =
        respData?['capability_limits'] as Map<String, dynamic>?;
    return CapabilityLimitsState(
      certificationMaleOnlyEnabled:
          capabilityLimits?['certification_male_only_enabled'] == true,
      certificationFemaleOnlyEnabled:
          capabilityLimits?['certification_female_only_enabled'] == true,
      profileEditCertifiedOnlyEnabled:
          capabilityLimits?['profile_edit_certified_only_enabled'] == true,
      momentPublishCertifiedOnlyEnabled:
          capabilityLimits?['moment_publish_certified_only_enabled'] == true,
    );
  }
}

/// App 初始化配置状态
class AppInitState {
  final bool isLoading;
  final bool loaded;
  final String coinName;
  final String diamondName;
  final int? imSdkAppId;
  final bool imConfigured;
  final bool customerServiceEnabled;
  final String? customerServiceUserId;
  final String customerServiceNickname;
  final String? customerServiceAvatar;
  final bool imTextBillingEnabled;
  final int imTextBillingPrice;
  final int imTextBillingAnchorShareBps;
  final List<int> certifiedCallPriceTiers;
  final CapabilityLimitsState capabilityLimits;

  const AppInitState({
    this.isLoading = false,
    this.loaded = false,
    this.coinName = '金币',
    this.diamondName = '钻石',
    this.imSdkAppId,
    this.imConfigured = false,
    this.customerServiceEnabled = false,
    this.customerServiceUserId,
    this.customerServiceNickname = '在线客服',
    this.customerServiceAvatar,
    this.imTextBillingEnabled = false,
    this.imTextBillingPrice = 0,
    this.imTextBillingAnchorShareBps = 5000,
    this.certifiedCallPriceTiers = const [],
    this.capabilityLimits = const CapabilityLimitsState(),
  });

  AppInitState copyWith({
    bool? isLoading,
    bool? loaded,
    String? coinName,
    String? diamondName,
    int? imSdkAppId,
    bool? imConfigured,
    bool? customerServiceEnabled,
    String? customerServiceUserId,
    String? customerServiceNickname,
    String? customerServiceAvatar,
    bool? imTextBillingEnabled,
    int? imTextBillingPrice,
    int? imTextBillingAnchorShareBps,
    List<int>? certifiedCallPriceTiers,
    CapabilityLimitsState? capabilityLimits,
  }) {
    return AppInitState(
      isLoading: isLoading ?? this.isLoading,
      loaded: loaded ?? this.loaded,
      coinName: coinName ?? this.coinName,
      diamondName: diamondName ?? this.diamondName,
      imSdkAppId: imSdkAppId ?? this.imSdkAppId,
      imConfigured: imConfigured ?? this.imConfigured,
      customerServiceEnabled:
          customerServiceEnabled ?? this.customerServiceEnabled,
      customerServiceUserId:
          customerServiceUserId ?? this.customerServiceUserId,
      customerServiceNickname:
          customerServiceNickname ?? this.customerServiceNickname,
      customerServiceAvatar:
          customerServiceAvatar ?? this.customerServiceAvatar,
      imTextBillingEnabled: imTextBillingEnabled ?? this.imTextBillingEnabled,
      imTextBillingPrice: imTextBillingPrice ?? this.imTextBillingPrice,
      imTextBillingAnchorShareBps:
          imTextBillingAnchorShareBps ?? this.imTextBillingAnchorShareBps,
      certifiedCallPriceTiers:
          certifiedCallPriceTiers ?? this.certifiedCallPriceTiers,
      capabilityLimits: capabilityLimits ?? this.capabilityLimits,
    );
  }

  static AppInitState fromBootstrapMap(Map<String, dynamic> respData) {
    final tokenNames = respData['token_names'] as Map<String, dynamic>?;
    final im = respData['im'] as Map<String, dynamic>?;
    final imTextBilling = respData['im_text_billing'] as Map<String, dynamic>?;
    final customerService =
        respData['customer_service'] as Map<String, dynamic>?;
    final sdkAppIdRaw = im?['sdk_app_id'];
    final sdkAppId = sdkAppIdRaw is num ? sdkAppIdRaw.toInt() : null;
    final imTextPriceRaw = imTextBilling?['price'];
    final imTextShareRaw = imTextBilling?['certified_user_share_bps'];
    final customerServiceUserId = _parseCustomerServiceUserId(
      customerService?['user_id'],
    );
    final capabilityLimits = CapabilityLimitsState.fromBootstrapMap(respData);
    final tierRaw = respData['certified_call_price_tiers'];
    final tiers = tierRaw is List
        ? tierRaw
              .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
              .whereType<int>()
              .where((item) => item >= 0)
              .toSet()
              .toList()
        : <int>[];
    tiers.sort();
    if (!tiers.contains(0)) tiers.insert(0, 0);

    return AppInitState(
      isLoading: false,
      loaded: true,
      coinName: tokenNames?['coin_name'] as String? ?? '金币',
      diamondName: tokenNames?['diamond_name'] as String? ?? '钻石',
      imConfigured: im?['configured'] == true,
      imSdkAppId: sdkAppId,
      customerServiceEnabled:
          customerService?['enabled'] == true && customerServiceUserId != null,
      customerServiceUserId: customerServiceUserId,
      customerServiceNickname: _parseCustomerServiceNickname(
        customerService?['nickname'],
      ),
      customerServiceAvatar: _parseCustomerServiceAvatar(
        customerService?['avatar'],
      ),
      imTextBillingEnabled: imTextBilling?['enabled'] == true,
      imTextBillingPrice: imTextPriceRaw is num
          ? imTextPriceRaw.toInt()
          : int.tryParse('${imTextPriceRaw ?? 0}') ?? 0,
      imTextBillingAnchorShareBps: imTextShareRaw is num
          ? imTextShareRaw.toInt()
          : int.tryParse('${imTextShareRaw ?? 5000}') ?? 5000,
      certifiedCallPriceTiers: tiers,
      capabilityLimits: capabilityLimits,
    );
  }

  static String? _parseCustomerServiceUserId(dynamic raw) {
    if (raw is int) {
      return raw > 0 ? raw.toString() : null;
    }
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value.toString() : null;
    }
    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty) return null;
      if (value.startsWith('chat_')) {
        final numeric = value.substring('chat_'.length);
        return int.tryParse(numeric)?.toString();
      }
      return int.tryParse(value)?.toString();
    }
    return null;
  }

  static String? _parseCustomerServiceAvatar(dynamic raw) {
    if (raw is String) {
      final value = raw.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static String _parseCustomerServiceNickname(dynamic raw) {
    if (raw is String) {
      final value = raw.trim();
      if (value.isNotEmpty) return value;
    }
    return '在线客服';
  }
}

/// 认证 Provider
class AuthNotifier extends StateNotifier<AuthState> {
  final DioClient _dio;

  AuthNotifier(this._dio) : super(const AuthState());

  int? _parseUserId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int? _parseNullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double _parseDouble(dynamic value, {double fallback = 0}) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  List<String> _parseAlbum(dynamic value) {
    final normalized = normalizeMediaPayload(value, parentKey: 'album_photos');
    if (normalized is! List) return const <String>[];
    return normalized
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// 初始化：检查登录状态
  Future<void> init() async {
    final token = StorageService.getToken();
    final localUserId = StorageService.getUserId();
    if (token != null && token.isNotEmpty) {
      // 尝试从本地缓存加载用户信息
      final cachedInfo = StorageService.getUserInfo();
      if (cachedInfo != null) {
        state = state.copyWith(
          isLoggedIn: true,
          userId: _parseUserId(cachedInfo['id']) ?? localUserId,
          username:
              cachedInfo['nickname'] as String? ??
              cachedInfo['username'] as String?,
          avatar: (normalizeMediaPayload(cachedInfo['avatar']) as String?)
              ?.trim(),
          signature: cachedInfo['signature'] as String?,
          gender: (cachedInfo['gender'] as String?) ?? 'male',
          birthDate: cachedInfo['birth_date'] as String?,
          heightCm: _parseNullableInt(cachedInfo['height_cm']),
          weightKg: _parseNullableInt(cachedInfo['weight_kg']),
          locationCity: cachedInfo['location_city'] as String?,
          albumPhotos: _parseAlbum(cachedInfo['album_photos']),
          coverUrl: (normalizeMediaPayload(cachedInfo['cover_url']) as String?)
              ?.trim(),
          isCertifiedUser: cachedInfo['is_certified_user'] == true,
          certificationStatus:
              (cachedInfo['certification_status'] as String?) ?? 'none',
          certifiedCallPrice:
              _parseNullableInt(cachedInfo['certified_call_price']) ?? 0,
          coins: _parseDouble(cachedInfo['coins']),
          diamonds: _parseDouble(cachedInfo['diamonds']),
        );
      } else {
        state = state.copyWith(isLoggedIn: true, userId: localUserId);
      }

      // 异步验证 token 并获取最新数据，失败则清除存储
      try {
        await fetchUserInfo();
      } catch (e) {
        await StorageService.clearUserData();
        state = const AuthState();
      }
    } else {
      state = const AuthState();
    }
  }

  /// 登录
  Future<bool> login({required String phone, String? password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _dio.apiPost(
        ApiEndpoints.appLogin,
        data: {'phone': phone, 'password': password ?? ''},
      );

      final code_ = data['code'] as int?;
      if (code_ != 200) {
        final msg = data['msg'] as String? ?? '登录失败';
        state = state.copyWith(isLoading: false, error: msg);
        return false;
      }

      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = state.copyWith(isLoading: false, error: '登录失败');
        return false;
      }

      final token = respData['token'] as String?;
      if (token == null) {
        state = state.copyWith(isLoading: false, error: 'Token 不存在');
        return false;
      }

      await StorageService.saveToken(token);
      final userId = _parseUserId(respData['user_id']);
      if (userId != null) {
        await StorageService.saveUserId(userId);
      }

      state = state.copyWith(
        isLoggedIn: true,
        userId: userId,
        username:
            respData['nickname'] as String? ?? respData['username'] as String?,
        avatar: (respData['avatar'] as String?)?.trim(),
        signature: respData['signature'] as String?,
        gender: (respData['gender'] as String?) ?? 'male',
        birthDate: respData['birth_date'] as String?,
        heightCm: _parseNullableInt(respData['height_cm']),
        weightKg: _parseNullableInt(respData['weight_kg']),
        locationCity: respData['location_city'] as String?,
        albumPhotos: _parseAlbum(respData['album_photos']),
        coverUrl: (respData['cover_url'] as String?)?.trim(),
        isCertifiedUser: respData['is_certified_user'] == true,
        certificationStatus:
            (respData['certification_status'] as String?) ?? 'none',
        certifiedCallPrice:
            _parseNullableInt(respData['certified_call_price']) ?? 0,
        coins: _parseDouble(respData['coins']),
        diamonds: _parseDouble(respData['diamonds']),
        isLoading: false,
      );

      await fetchUserInfo();

      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '网络错误，请重试');
      return false;
    }
  }

  /// 获取用户信息
  Future<void> fetchUserInfo() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.userInfo);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;

      final nextAvatar = (respData['avatar'] as String?)?.trim() ?? '';
      final currentAvatar = state.avatar?.trim();
      // 管理后台修改头像但 URL 不变时，主动清理图片缓存，避免继续展示旧图
      if (nextAvatar.isNotEmpty &&
          currentAvatar != null &&
          currentAvatar.isNotEmpty &&
          nextAvatar == currentAvatar) {
        imageCache.evict(NetworkImage(nextAvatar));
      }

      final userId = _parseUserId(respData['id']);
      if (userId != null) {
        await StorageService.saveUserId(userId);
        await StorageService.saveUserInfo(respData);
      }

      state = state.copyWith(
        isLoggedIn: true,
        userId: userId,
        username:
            respData['nickname'] as String? ?? respData['username'] as String?,
        avatar: nextAvatar,
        signature: respData['signature'] as String?,
        gender: (respData['gender'] as String?) ?? 'male',
        birthDate: respData['birth_date'] as String?,
        heightCm: _parseNullableInt(respData['height_cm']),
        weightKg: _parseNullableInt(respData['weight_kg']),
        locationCity: respData['location_city'] as String?,
        albumPhotos: _parseAlbum(respData['album_photos']),
        coverUrl: (respData['cover_url'] as String?)?.trim(),
        isCertifiedUser: respData['is_certified_user'] == true,
        certificationStatus:
            (respData['certification_status'] as String?) ?? 'none',
        certifiedCallPrice:
            _parseNullableInt(respData['certified_call_price']) ?? 0,
        coins: _parseDouble(respData['coins']),
        diamonds: _parseDouble(respData['diamonds']),
      );
    } on UnauthorizedException {
      // Token 无效，清除存储
      await StorageService.clearUserData();
      state = const AuthState();
      rethrow;
    } catch (e) {
      AppLogger.debug('auth.fetchUserInfo error: $e');
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> payload) async {
    try {
      state = state.copyWith(clearLastProfileUpdateData: true);
      final data = await _dio.apiPost(
        ApiEndpoints.userProfileUpdate,
        data: payload,
      );
      final code = data['code'] as int?;
      if (code != 200) {
        final msg = data['msg'] as String? ?? '更新资料失败';
        state = state.copyWith(error: msg);
        return false;
      }
      final respData = data['data'] as Map<String, dynamic>?;
      state = respData == null
          ? state.copyWith(clearLastProfileUpdateData: true)
          : state.copyWith(lastProfileUpdateData: respData);
      await fetchUserInfo();
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(error: '网络错误，请重试');
      return false;
    }
  }

  Future<String?> uploadProfileImage({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final prepared = await ImageUploadPreprocessor.instance.prepareImage(
        bytes: bytes,
        filename: filename,
        scene: ImageUploadScene.avatar,
      );
      AppLogger.debug(
        'auth.uploadProfileImage start: filename=$filename, '
        'bytes=${bytes.length}, uploadBytes=${prepared.bytes.length}, '
        'compressed=${prepared.compressed}',
      );
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          prepared.bytes,
          filename: prepared.filename,
        ),
      });
      final resp = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.userUploadImage,
        data: formData,
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '上传失败';
        state = state.copyWith(error: msg);
        AppLogger.debug(
          'auth.uploadProfileImage fail: business code=${data['code']} msg=$msg',
        );
        return null;
      }
      final url = (data['data'] as Map<String, dynamic>?)?['url'] as String?;
      AppLogger.debug('auth.uploadProfileImage success: url=$url');
      return (url == null || url.trim().isEmpty) ? null : url.trim();
    } on ImageUploadPreprocessException catch (e) {
      state = state.copyWith(error: e.message);
      AppLogger.debug('auth.uploadProfileImage preprocess error: ${e.message}');
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      AppLogger.debug('auth.uploadProfileImage ApiException: ${e.message}');
      return null;
    } on NetworkException catch (e) {
      state = state.copyWith(error: e.message);
      AppLogger.debug('auth.uploadProfileImage NetworkException: ${e.message}');
      return null;
    } catch (e) {
      state = state.copyWith(error: '上传失败，请重试');
      AppLogger.debug('auth.uploadProfileImage unexpected error: $e');
      return null;
    }
  }

  /// 刷新余额
  Future<void> refreshBalance() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.walletBalance);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;

      final coins = _parseDouble(respData['coins'], fallback: state.coins);
      final diamonds = _parseDouble(
        respData['diamonds'],
        fallback: state.diamonds,
      );
      syncBalance(coins: coins, diamonds: diamonds);
    } catch (e) {
      AppLogger.debug('auth.refreshBalance error: $e');
    }
  }

  /// 同步余额到全局状态（避免必须重新登录才更新）
  /// - `coins`/`diamonds` 为空时保持当前值
  /// - 同步更新本地缓存余额字段
  void syncBalance({double? coins, double? diamonds}) {
    final nextCoins = coins ?? state.coins;
    final nextDiamonds = diamonds ?? state.diamonds;
    state = state.copyWith(coins: nextCoins, diamonds: nextDiamonds);

    final cached = StorageService.getUserInfo();
    if (cached == null) return;
    cached['coins'] = nextCoins;
    cached['diamonds'] = nextDiamonds;
    StorageService.saveUserInfo(cached);
  }

  /// 注册成功后设置登录状态（token已保存）
  void setLoggedInAfterRegister({required int userId, required String gender}) {
    state = state.copyWith(isLoggedIn: true, userId: userId, gender: gender);
  }

  /// 退出登录
  Future<void> logout() async {
    await StorageService.clearUserData();
    WsService.instance.disconnect();
    state = const AuthState();
  }
}

/// App 初始化配置 Provider
class AppInitNotifier extends StateNotifier<AppInitState> {
  final DioClient _dio;

  AppInitNotifier(this._dio) : super(const AppInitState());

  Future<void> init() async {
    if (state.loaded || state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final data = await _dio.apiGet(ApiEndpoints.appBootstrap);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = state.copyWith(isLoading: false, loaded: true);
        return;
      }
      state = AppInitState.fromBootstrapMap(respData);
    } catch (e) {
      AppLogger.debug('appInit.init error: $e');
      state = state.copyWith(isLoading: false, loaded: true);
    }
  }
}

/// 认证 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(DioClient.instance);
});

/// App 初始化配置 Provider
final appInitProvider = StateNotifierProvider<AppInitNotifier, AppInitState>((
  ref,
) {
  return AppInitNotifier(DioClient.instance);
});

/// 代币名称 Provider
final tokenNamesProvider = Provider<TokenNamesState>((ref) {
  final initState = ref.watch(appInitProvider);
  return TokenNamesState(
    coinName: initState.coinName,
    diamondName: initState.diamondName,
  );
});

/// 是否已登录
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});
