import 'package:go_router/go_router.dart';
import '../../modules/auth/splash_page.dart';
import '../../modules/auth/login_page.dart';
import '../../modules/auth/register_page.dart';
import '../../modules/home/home_page.dart';
import '../../modules/home/discover_page.dart';
import '../../modules/home/messages_page.dart';
import '../../modules/home/profile_page.dart';
import '../../modules/home/main_shell.dart';
import '../../modules/home/anchor_apply_page.dart';
import '../../modules/call/call_room_page.dart';
import '../../modules/profile/recharge_page.dart';
import '../../modules/profile/edit_profile_page.dart';
import '../../modules/settings/settings_page.dart';
import '../../modules/settings/agreement_page.dart';
import '../../modules/settings/privacy_page.dart';
import '../../modules/settings/change_password_page.dart';
import '../../modules/im/im_page.dart';
import '../../modules/gift/gift_panel.dart';
import '../../modules/home/anchor_detail_page.dart';
import '../../modules/home/wallet_page.dart';
import '../../app/providers/anchor_provider.dart';
import '../../core/storage/storage.dart';

class AppRoutes {
  AppRoutes._();
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String index = '/index';
  static const String discover = '/discover';
  static const String messages = '/messages';
  static const String anchorDetail = '/anchor/detail';
  static const String profile = '/profile';
  static const String recharge = '/profile/recharge';
  static const String wallet = '/wallet';
  static const String editProfile = '/profile/edit';
  static const String settings = '/settings';
  static const String settingsAgreement = '/settings/agreement';
  static const String settingsPrivacy = '/settings/privacy';
  static const String settingsPassword = '/settings/password';
  static const String anchorApply = '/anchor/apply';
  static const String im = '/im';
  static const String giftPanel = '/gift';
  static const String callRoom = '/call/room';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  redirect: (context, state) {
    final isLoggedIn = StorageService.getToken() != null;
    final isOnSplash = state.matchedLocation == AppRoutes.splash;
    final isOnLogin = state.matchedLocation == AppRoutes.login;
    final isOnRegister = state.matchedLocation == AppRoutes.register;
    if (isOnSplash) { return null; }
    if (!isLoggedIn && !isOnLogin && !isOnRegister) { return AppRoutes.login; }
    if (isLoggedIn && (isOnLogin || isOnRegister)) { return AppRoutes.index; }
    return null;
  },
  routes: [
    GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashPage()),
    GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
    GoRoute(path: AppRoutes.register, builder: (context, state) => const RegisterPage()),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: AppRoutes.index, pageBuilder: (context, state) => NoTransitionPage(child: HomePage())),
        GoRoute(path: AppRoutes.discover, pageBuilder: (context, state) => NoTransitionPage(child: DiscoverPage())),
        GoRoute(path: AppRoutes.messages, pageBuilder: (context, state) => NoTransitionPage(child: MessagesPage())),
        GoRoute(path: AppRoutes.profile, pageBuilder: (context, state) => NoTransitionPage(child: ProfilePage())),
      ],
    ),
    GoRoute(path: AppRoutes.callRoom, builder: (context, state) => CallRoomPage(roomId: state.uri.queryParameters['roomId'] ?? '', anchorId: state.uri.queryParameters['anchorId'] ?? '')),
    GoRoute(path: AppRoutes.anchorDetail, builder: (context, state) => AnchorDetailPage(anchor: state.extra as AnchorInfo)),
    GoRoute(path: AppRoutes.recharge, builder: (context, state) => const RechargePage()),
    GoRoute(path: AppRoutes.wallet, builder: (context, state) => const WalletPage()),
    GoRoute(path: AppRoutes.editProfile, builder: (context, state) => const EditProfilePage()),
    GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPage()),
    GoRoute(path: AppRoutes.settingsAgreement, builder: (context, state) => const AgreementPage()),
    GoRoute(path: AppRoutes.settingsPrivacy, builder: (context, state) => const PrivacyPage()),
    GoRoute(path: AppRoutes.settingsPassword, builder: (context, state) => const ChangePasswordPage()),
    GoRoute(path: AppRoutes.anchorApply, builder: (context, state) => const AnchorApplyPage()),
    GoRoute(path: '${AppRoutes.im}/:userId', builder: (context, state) => ImPage(userId: state.pathParameters['userId']!)),
    GoRoute(path: AppRoutes.giftPanel, builder: (context, state) => GiftPanel(anchorId: state.uri.queryParameters['anchorId'] ?? '', onClose: () => context.pop())),
  ],
);
