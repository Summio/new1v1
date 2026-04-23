import 'package:flutter/material.dart';

/// App 主题配置 - 梦幻马卡龙风格
class AppTheme {
  AppTheme._();

  // ============ 核心色板 ============
  /// 电感蓝 - 主色 (比粉色更具高级感和信任感)
  static const Color primaryColor = Color(0xFF007AFF);
  /// 亮青色 - 辅助色
  static const Color accentColor = Color(0xFF00FBFF);
  /// 在线绿
  static const Color onlineGreen = Color(0xFF34C759);
  /// 离线灰
  static const Color offlineGray = Color(0xFFC7C7CC);
  /// 辅色 - 浅蓝色系
  static const Color secondaryColor = Color(0xFF5AC8FA);
  /// 深辅色
  static const Color secondaryDark = Color(0xFF007AFF);
  /// 纯黑标题
  static const Color textPrimary = Color(0xFF000000);
  /// 辅助灰
  static const Color textSecondary = Color(0xFF8E8E93);
  /// 占位灰
  static const Color textHint = Color(0xFFC7C7CC);
  /// 极浅灰背景
  static const Color backgroundColor = Color(0xFFFFFFFF);
  /// 容器表面色
  static const Color surfaceColor = Color(0xFFF2F2F7);
  /// 占位背景色
  static const Color placeholderColor = Color(0xFFEFEFF4);
  /// 珊瑚红 - 错误/挂断
  static const Color errorColor = Color(0xFFFF3B30);
  /// 分隔线
  static const Color dividerColor = Color(0xFFE5E5EA);
  /// 钻石金色
  static const Color diamondGold = Color(0xFFFFD700);
  /// 卡片背景色
  static const Color cardBackground = Color(0xFFF2F2F7);
  /// 微弱阴影色
  static Color get shadowLight => Colors.black.withValues(alpha: 0.04);
  /// 中等阴影色
  static Color get overlayMedium => Colors.black.withValues(alpha: 0.4);
  /// 徽章背景色
  static Color get badgeBackground => Colors.white.withValues(alpha: 0.9);
  /// 次要文字色（带透明度）
  static Color get textSecondaryFaint => Colors.white.withValues(alpha: 0.8);

  // ============ 渐变 ============
  /// 仅在核心通话按钮使用的渐变 - 更有深度的蓝色
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF007AFF), Color(0xFF00C7FF)],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  /// 视频呼叫专属渐变
  static const LinearGradient callGradient = LinearGradient(
    colors: [Color(0xFF007AFF), Color(0xFF0055FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// 余额卡片 - 深邃黑金风格 (更有品质感)
  static const LinearGradient balanceGradient = LinearGradient(
    colors: [Color(0xFF1C1C1E), Color(0xFF3A3A3C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ============ 阴影 ============
  /// 极其微弱的投影，甚至不使用投影改用边框
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: primaryColor.withValues(alpha: 0.1),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  // ============ 圆角 ============
  /// 卡片圆角
  static const double radiusCard = 20.0;
  /// 按钮圆角
  static const double radiusButton = 16.0;
  /// 输入框圆角
  static const double radiusInput = 14.0;
  /// 标签圆角
  static const double radiusTag = 8.0;

  // ============ ThemeData ============
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: backgroundColor,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitionsBuilder(),
        TargetPlatform.iOS: _NoTransitionsBuilder(),
        TargetPlatform.macOS: _NoTransitionsBuilder(),
        TargetPlatform.windows: _NoTransitionsBuilder(),
        TargetPlatform.linux: _NoTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoTransitionsBuilder(),
      },
    ),
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: surfaceColor,
      error: errorColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: const BorderSide(color: dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: const BorderSide(color: dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusInput),
        borderSide: const BorderSide(color: errorColor),
      ),
      hintStyle: const TextStyle(color: textHint),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceColor,
      selectedItemColor: primaryColor,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: dividerColor,
      thickness: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        color: textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        color: textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        color: textHint,
      ),
    ),
  );
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
