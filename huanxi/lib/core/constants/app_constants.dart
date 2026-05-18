/// App 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '欢喜';
  static const String appVersion = '1.0.0';

  /// API 基础地址
  /// 必须通过 Dart define 显式配置，避免不同环境误连默认地址。
  static String get apiBaseUrl {
    // 编译时传入: flutter build --dart-define=API_BASE_URL=https://api.example.com
    const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final value = env.trim();
    if (value.isNotEmpty) {
      return value;
    }
    throw StateError('必须通过 --dart-define=API_BASE_URL=... 配置 API 地址');
  }

  /// 本地存储 Keys
  static const String storageToken = 'token';
  static const String storageUserId = 'user_id';
  static const String storageUserInfo = 'user_info';
  static const String storageInitialProfileCompleted =
      'initial_profile_completed';
  static const String storageGiftList = 'gift_list';
  static const String storageCertifiedUserList = 'certified_user_list';
  static const String storageFirstLaunch = 'first_launch';
  static const String storageDarkMode = 'dark_mode';
  static const String storageTeenModeState = 'teen_mode_state';
  static const String storageKeepAliveEnabled = 'keep_alive_enabled';

  /// Hive Box Names
  static const String hiveBoxUser = 'user_box';
  static const String hiveBoxCache = 'cache_box';
  static const String hiveBoxSettings = 'settings_box';

  /// 心跳间隔（毫秒）
  static const int heartbeatIntervalMs = 5000;

  /// 请求超时时间（毫秒）
  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 15000;
  static const int sendTimeoutMs = 15000;

  /// 分页默认每页数量
  static const int defaultPageSize = 20;
}
