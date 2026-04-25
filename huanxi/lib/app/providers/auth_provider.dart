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
  final String gender;
  final String? birthDate;
  final int? heightCm;
  final int? weightKg;
  final String? locationCity;
  final List<String> albumPhotos;
  final String? coverUrl;
  final String? appRole;
  final int coins;
  final int diamonds;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.userId,
    this.username,
    this.avatar,
    this.gender = 'secret',
    this.birthDate,
    this.heightCm,
    this.weightKg,
    this.locationCity,
    this.albumPhotos = const [],
    this.coverUrl,
    this.appRole,
    this.coins = 0,
    this.diamonds = 0,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    int? userId,
    String? username,
    String? avatar,
    String? gender,
    String? birthDate,
    int? heightCm,
    int? weightKg,
    String? locationCity,
    List<String>? albumPhotos,
    String? coverUrl,
    String? appRole,
    int? coins,
    int? diamonds,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      locationCity: locationCity ?? this.locationCity,
      albumPhotos: albumPhotos ?? this.albumPhotos,
      coverUrl: coverUrl ?? this.coverUrl,
      appRole: appRole ?? this.appRole,
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
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

/// App 初始化配置状态
class AppInitState {
  final bool isLoading;
  final bool loaded;
  final String coinName;
  final String diamondName;
  final int? imSdkAppId;
  final bool imConfigured;
  final String? faceBeautyKey;

  const AppInitState({
    this.isLoading = false,
    this.loaded = false,
    this.coinName = '金币',
    this.diamondName = '钻石',
    this.imSdkAppId,
    this.imConfigured = false,
    this.faceBeautyKey,
  });

  AppInitState copyWith({
    bool? isLoading,
    bool? loaded,
    String? coinName,
    String? diamondName,
    int? imSdkAppId,
    bool? imConfigured,
    Object? faceBeautyKey = const _NoValue(),
  }) {
    return AppInitState(
      isLoading: isLoading ?? this.isLoading,
      loaded: loaded ?? this.loaded,
      coinName: coinName ?? this.coinName,
      diamondName: diamondName ?? this.diamondName,
      imSdkAppId: imSdkAppId ?? this.imSdkAppId,
      imConfigured: imConfigured ?? this.imConfigured,
      faceBeautyKey: identical(faceBeautyKey, const _NoValue())
          ? this.faceBeautyKey
          : faceBeautyKey as String?,
    );
  }
}

class _NoValue {
  const _NoValue();
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
          gender: (cachedInfo['gender'] as String?) ?? 'secret',
          birthDate: cachedInfo['birth_date'] as String?,
          heightCm: _parseNullableInt(cachedInfo['height_cm']),
          weightKg: _parseNullableInt(cachedInfo['weight_kg']),
          locationCity: cachedInfo['location_city'] as String?,
          albumPhotos: _parseAlbum(cachedInfo['album_photos']),
          coverUrl: (normalizeMediaPayload(cachedInfo['cover_url']) as String?)
              ?.trim(),
          appRole: cachedInfo['is_anchor'] == true ? 'anchor' : 'user',
          coins: cachedInfo['coins'] as int? ?? 0,
          diamonds: cachedInfo['diamonds'] as int? ?? 0,
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
        gender: (respData['gender'] as String?) ?? 'secret',
        birthDate: respData['birth_date'] as String?,
        heightCm: _parseNullableInt(respData['height_cm']),
        weightKg: _parseNullableInt(respData['weight_kg']),
        locationCity: respData['location_city'] as String?,
        albumPhotos: _parseAlbum(respData['album_photos']),
        coverUrl: (respData['cover_url'] as String?)?.trim(),
        appRole: respData['is_anchor'] == true ? 'anchor' : 'user',
        coins: respData['coins'] as int? ?? 0,
        diamonds: respData['diamonds'] as int? ?? 0,
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
        gender: (respData['gender'] as String?) ?? 'secret',
        birthDate: respData['birth_date'] as String?,
        heightCm: _parseNullableInt(respData['height_cm']),
        weightKg: _parseNullableInt(respData['weight_kg']),
        locationCity: respData['location_city'] as String?,
        albumPhotos: _parseAlbum(respData['album_photos']),
        coverUrl: (respData['cover_url'] as String?)?.trim(),
        appRole: respData['is_anchor'] == true ? 'anchor' : 'user',
        coins: respData['coins'] as int? ?? 0,
        diamonds: respData['diamonds'] as int? ?? 0,
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

      final coins = respData['coins'] as int? ?? state.coins;
      final diamonds = respData['diamonds'] as int? ?? state.diamonds;
      syncBalance(coins: coins, diamonds: diamonds);
    } catch (e) {
      AppLogger.debug('auth.refreshBalance error: $e');
    }
  }

  /// 同步余额到全局状态（避免必须重新登录才更新）
  /// - `coins`/`diamonds` 为空时保持当前值
  /// - 同步更新本地缓存余额字段
  void syncBalance({int? coins, int? diamonds}) {
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
  void setLoggedInAfterRegister({required int userId}) {
    state = state.copyWith(isLoggedIn: true, userId: userId);
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

      final tokenNames = respData['token_names'] as Map<String, dynamic>?;
      final im = respData['im'] as Map<String, dynamic>?;
      final sdkAppIdRaw = im?['sdk_app_id'];
      final sdkAppId = sdkAppIdRaw is num ? sdkAppIdRaw.toInt() : null;
      final faceBeautyKey = respData['face_beauty']?['key'] as String?;

      state = state.copyWith(
        isLoading: false,
        loaded: true,
        coinName: tokenNames?['coin_name'] as String? ?? '金币',
        diamondName: tokenNames?['diamond_name'] as String? ?? '钻石',
        imConfigured: im?['configured'] == true,
        imSdkAppId: sdkAppId,
        faceBeautyKey: faceBeautyKey,
      );
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

/// FaceBeauty SDK Key Provider
final faceBeautyKeyProvider = Provider<String?>((ref) {
  return ref.watch(appInitProvider).faceBeautyKey;
});
