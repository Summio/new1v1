/// App 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '欢喜';
  static const String appVersion = '1.0.0';

  /// API 基础地址
  /// 必须通过 Dart define 显式配置，避免不同环境误连默认地址。
  static String get apiBaseUrl {
    // 编译时传入: flutter build --dart-define=API_BASE_URL=https://api.example.com
    final env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
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
  static const String storageGiftList = 'gift_list';
  static const String storageAnchorList = 'anchor_list';
  static const String storageFirstLaunch = 'first_launch';
  static const String storageDarkMode = 'dark_mode';

  /// 美颜参数存储 Keys
  static const String beautyWhitening = 'beauty_whitening';
  static const String beautyBlurriness = 'beauty_blurriness';
  static const String beautyRosiness = 'beauty_rosiness';
  static const String beautyClearness = 'beauty_clearness';
  static const String beautyBrightness = 'beauty_brightness';
  static const String beautyEyeEnlarging = 'beauty_eye_enlarging';
  static const String beautyEyeRounding = 'beauty_eye_rounding';
  static const String beautyCheekThinning = 'beauty_cheek_thinning';
  static const String beautyCheekV = 'beauty_cheek_v';
  static const String beautyCheekNarrowing = 'beauty_cheek_narrowing';
  static const String beautyChin = 'beauty_chin';
  static const String beautyForehead = 'beauty_forehead';
  static const String beautyNoseThinning = 'beauty_nose_thinning';
  static const String beautyIsBeautyEnabled = 'beauty_is_beauty_enabled';
  static const String beautyIsFaceShapeEnabled = 'beauty_is_face_shape_enabled';
  static const String beautyIsRenderEnabled = 'beauty_is_render_enabled';
  static const String beautyCurrentFilter = 'beauty_current_filter';
  static const String beautyFilterIntensity = 'beauty_filter_intensity';

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
