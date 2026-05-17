import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/permissions/mandatory_permission_service.dart';
import '../../services/im_service.dart';

/// Splash 页面
/// 负责：SDK 初始化、登录态检查、路由跳转
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _init();
    });
  }

  Future<void> _init() async {
    try {
      // 初始化认证状态 + App 启动配置，设置一个总的超时兜底
      await Future.wait([
        ref.read(authProvider.notifier).init(),
        ref.read(appInitProvider.notifier).init(),
      ]).timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Splash Init Error: $e');
    }

    // 全局初始化 IM SDK（不依赖登录状态，提前注册消息监听器）
    await _initGlobalIM();

    // 无论如何，稍微展示一下品牌 Logo
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final isLoggedIn = ref.read(authProvider).isLoggedIn;
    debugPrint('Splash Init Finished. IsLoggedIn: $isLoggedIn');

    // 根据登录状态跳转
    if (isLoggedIn) {
      try {
        final permissionState = await MandatoryPermissionService.instance
            .check();
        if (!mounted) return;
        if (permissionState.requiredGranted) {
          context.go(AppRoutes.index);
        } else {
          context.go(AppRoutes.mandatoryPermissions);
        }
      } catch (e) {
        debugPrint('Splash Permission Check Error: $e');
        if (!mounted) return;
        context.go(AppRoutes.mandatoryPermissions);
      }
    } else {
      context.go(AppRoutes.login);
    }
  }

  /// 全局初始化 IM SDK，确保在任何页面使用前就绪
  Future<void> _initGlobalIM() async {
    final appInit = ref.read(appInitProvider);
    final auth = ref.read(authProvider);

    if (!appInit.imConfigured || appInit.imSdkAppId == null) {
      debugPrint('[Splash] IM 未配置，跳过全局初始化');
      return;
    }

    final imService = IMService();
    try {
      // 1. 全局初始化 SDK（仅注册监听器，不登录）
      await imService.initGlobal(sdkAppId: appInit.imSdkAppId!);

      // 2. 如果已登录，立即完成 IM 登录
      if (auth.isLoggedIn && auth.userId != null) {
        debugPrint('[Splash] 已登录用户，进行 IM 登录...');
        // IM 登录需要 usersig，需要从后端获取
        // 这部分逻辑由 MainShell 中的 _initGlobalIMUnread 统一处理
        // 这里只确保 SDK 已初始化
      }
    } catch (e) {
      debugPrint('[Splash] IM 全局初始化失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          // 装饰性圆形背景
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            right: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            top: 120,
            right: 40,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondaryColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          // 内容
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo 渐变容器
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                // App名称 - 渐变文字
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppTheme.primaryGradient.createShader(bounds),
                  child: const Text(
                    '欢喜',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1v1 视频交友',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
