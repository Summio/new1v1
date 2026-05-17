import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/storage.dart';
import 'core/network/dio_client.dart';
import 'core/device/screen_awake_service.dart';
import 'app/theme/app_theme.dart';
import 'app/routes/app_router.dart';
import 'services/teen_mode_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局锁定竖屏，禁用旋转相关提示/行为
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 初始化本地存储
  await StorageService.init();
  await TeenModeService.instance.repairInvalidState();

  // 初始化 Dio
  DioClient.instance.init();

  // App 前台全局保持屏幕常亮，避免通话、来电等待等场景自动锁屏
  await ScreenAwakeService.instance.enableGlobal();

  runApp(
    const ProviderScope(
      child: HuanxiApp(),
    ),
  );
}

class HuanxiApp extends StatelessWidget {
  const HuanxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '欢喜',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return _AppKeepAwake(
          child: HeroMode(
            enabled: false,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _AppKeepAwake extends StatefulWidget {
  const _AppKeepAwake({required this.child});

  final Widget child;

  @override
  State<_AppKeepAwake> createState() => _AppKeepAwakeState();
}

class _AppKeepAwakeState extends State<_AppKeepAwake>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ScreenAwakeService.instance.reapplyIfNeeded());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ScreenAwakeService.instance.reapplyIfNeeded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
