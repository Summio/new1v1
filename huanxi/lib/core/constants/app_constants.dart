/// App 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '欢喜';
  static const String appVersion = '1.0.0';

  /// API 基础地址
  /// 开发环境指向后端服务
  /// 生产环境需改为实际服务器地址或通过环境变量配置
  static String get apiBaseUrl {
    // 可通过 Dart define 或环境变量切换
    // 编译时传入: flutter build --dart-define=API_BASE_URL=https://api.example.com
    final env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (env.isNotEmpty) return env;
    return 'http://192.168.100.199:9999/api/v1/';
  }

  /// 本地存储 Keys
  static const String storageToken = 'token';
  static const String storageUserId = 'user_id';
  static const String storageUserInfo = 'user_info';
  static const String storageGiftList = 'gift_list';
  static const String storageAnchorList = 'anchor_list';
  static const String storageFirstLaunch = 'first_launch';
  static const String storageDarkMode = 'dark_mode';

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
