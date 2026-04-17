import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/storage.dart';
import 'core/network/dio_client.dart';
import 'app/theme/app_theme.dart';
import 'app/routes/app_router.dart';

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

  // 初始化 Dio
  DioClient.instance.init();

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
      builder: (context, child) {
        return HeroMode(
          enabled: false,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
