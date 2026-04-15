import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/storage/storage.dart';
import '../../core/network/api_exception.dart';

/// 认证状态
class AuthState {
  final bool isLoggedIn;
  final int? userId;
  final String? username;
  final String? avatar;
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
      appRole: appRole ?? this.appRole,
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 代币名称状态（coin_name, diamond_name）
class TokenNamesState {
  final String coinName;
  final String diamondName;

  const TokenNamesState({
    this.coinName = '金币',
    this.diamondName = '钻石',
  });

  TokenNamesState copyWith({
    String? coinName,
    String? diamondName,
  }) {
    return TokenNamesState(
      coinName: coinName ?? this.coinName,
      diamondName: diamondName ?? this.diamondName,
    );
  }
}

/// 认证 Provider
class AuthNotifier extends StateNotifier<AuthState> {
  final DioClient _dio;

  AuthNotifier(this._dio) : super(const AuthState());

  /// 初始化：检查登录状态
  Future<void> init() async {
    final token = StorageService.getToken();
    if (token != null && token.isNotEmpty) {
      // 尝试从本地缓存加载用户信息
      final cachedInfo = StorageService.getUserInfo();
      if (cachedInfo != null) {
        state = state.copyWith(
          isLoggedIn: true,
          userId: cachedInfo['id'] as int?,
          username: cachedInfo['nickname'] as String? ?? cachedInfo['username'] as String?,
          avatar: cachedInfo['avatar'] as String?,
          appRole: cachedInfo['is_anchor'] == true ? 'anchor' : 'user',
          coins: cachedInfo['coins'] as int? ?? 0,
          diamonds: cachedInfo['diamonds'] as int? ?? 0,
        );
      } else {
        state = state.copyWith(isLoggedIn: true);
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
  Future<bool> login({
    required String phone,
    String? password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _dio.apiPost(
        ApiEndpoints.appLogin,
        data: {
          'phone': phone,
          'password': password ?? '',
        },
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
      final userId = respData['user_id'] as int?;
      if (userId != null) {
        await StorageService.saveUserId(userId);
      }

      state = state.copyWith(
        isLoggedIn: true,
        userId: userId,
        username: respData['nickname'] as String? ?? respData['username'] as String?,
        avatar: respData['avatar'] as String?,
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

      final userId = respData['id'] as int?;
      if (userId != null) {
        await StorageService.saveUserId(userId);
        await StorageService.saveUserInfo(respData);
      }

      state = state.copyWith(
        isLoggedIn: true,
        userId: userId,
        username: respData['nickname'] as String? ?? respData['username'] as String?,
        avatar: respData['avatar'] as String?,
        appRole: respData['is_anchor'] == true ? 'anchor' : 'user',
        coins: respData['coins'] as int? ?? 0,
        diamonds: respData['diamonds'] as int? ?? 0,
      );
    } on UnauthorizedException {
      // Token 无效，清除存储
      await StorageService.clearUserData();
      state = const AuthState();
      rethrow;
    } catch (_) {
      // 静默失败
    }
  }

  /// 刷新余额
  Future<void> refreshBalance() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.walletBalance);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;

      state = state.copyWith(
        coins: respData['coins'] as int? ?? state.coins,
        diamonds: respData['diamonds'] as int? ?? state.diamonds,
      );
    } catch (_) {
      // 静默失败
    }
  }

  /// 注册成功后设置登录状态（token已保存）
  void setLoggedInAfterRegister({required int userId}) {
    state = state.copyWith(isLoggedIn: true, userId: userId);
  }

  /// 退出登录
  Future<void> logout() async {
    await StorageService.clearUserData();
    state = const AuthState();
  }
}

/// 代币名称 Provider
class TokenNamesNotifier extends StateNotifier<TokenNamesState> {
  final DioClient _dio;

  TokenNamesNotifier(this._dio) : super(const TokenNamesState());

  Future<void> fetchTokenNames() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.systemConfig);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;

      state = state.copyWith(
        coinName: respData['coin_name'] as String? ?? '金币',
        diamondName: respData['diamond_name'] as String? ?? '钻石',
      );
    } catch (_) {
      // 静默失败，使用默认值
    }
  }
}

/// 认证 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(DioClient.instance);
});

/// 代币名称 Provider
final tokenNamesProvider =
    StateNotifierProvider<TokenNamesNotifier, TokenNamesState>((ref) {
  return TokenNamesNotifier(DioClient.instance);
});

/// 是否已登录
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});
