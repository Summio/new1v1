import 'package:flutter/material.dart';
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
import '../../modules/call/call_outgoing_page.dart';
import '../../modules/call/incoming_call_page.dart';
import '../../modules/profile/recharge_page.dart';
import '../../modules/profile/coin_transactions_page.dart';
import '../../modules/profile/diamond_transactions_page.dart';
import '../../modules/profile/withdraw_account_page.dart';
import '../../modules/profile/withdraw_page.dart';
import '../../modules/profile/edit_profile_page.dart';
import '../../modules/settings/settings_page.dart';
import '../../modules/settings/agreement_page.dart';
import '../../modules/settings/privacy_page.dart';
import '../../modules/settings/change_password_page.dart';
import '../../modules/im/im_page.dart';
import '../../modules/gift/gift_panel.dart';
import '../../modules/home/my_moments_page.dart';
import '../../modules/home/publish_moment_page.dart';
import '../../modules/home/anchor_detail_page.dart';
import '../../modules/home/my_following_page.dart';
import '../../modules/home/user_search_page.dart';
import '../../modules/home/call_page.dart';
import '../../app/providers/anchor_provider.dart';
import '../../app/providers/wallet_provider.dart';
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
  static const String userSearch = '/search';
  static const String profile = '/profile';
  static const String recharge = '/profile/recharge';
  static const String withdraw = '/profile/withdraw';
  static const String withdrawAccount = '/profile/withdraw/account';
  static const String coinTransactions = '/profile/recharge/transactions';
  static const String diamondTransactions = '/profile/diamond/transactions';
  static const String callHistory = '/profile/call-history';
  static const String editProfile = '/profile/edit';
  static const String settings = '/settings';
  static const String settingsAgreement = '/settings/agreement';
  static const String settingsPrivacy = '/settings/privacy';
  static const String settingsPassword = '/settings/password';
  static const String anchorApply = '/anchor/apply';
  static const String im = '/im';
  static const String giftPanel = '/gift';
  static const String myMoments = '/profile/moments';
  static const String myFollowing = '/profile/following';
  static const String myFans = '/profile/fans';
  static const String publishMoment = '/moment/publish';
  static const String callRoom = '/call/room';
  static const String callOutgoing = '/call/outgoing';
  static const String callIncoming = '/call/incoming';

  static AnchorInfo? tryGetAnchorInfo(Object? extra) {
    return extra is AnchorInfo ? extra : null;
  }
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  redirect: (context, state) {
    final token = StorageService.getToken();
    final isLoggedIn = token != null && token.isNotEmpty;
    final isOnSplash = state.matchedLocation == AppRoutes.splash;
    final isOnLogin = state.matchedLocation == AppRoutes.login;
    final isOnRegister = state.matchedLocation == AppRoutes.register;
    if (isOnSplash) {
      return null;
    }
    if (!isLoggedIn && !isOnLogin && !isOnRegister) {
      return AppRoutes.login;
    }
    if (isLoggedIn && (isOnLogin || isOnRegister)) {
      return AppRoutes.index;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: AppRoutes.register,
      builder: (context, state) => const RegisterPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.index,
          pageBuilder: (context, state) => NoTransitionPage(child: HomePage()),
        ),
        GoRoute(
          path: AppRoutes.discover,
          pageBuilder: (context, state) =>
              NoTransitionPage(child: DiscoverPage()),
        ),
        GoRoute(
          path: AppRoutes.messages,
          pageBuilder: (context, state) =>
              NoTransitionPage(child: MessagesPage()),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (context, state) =>
              NoTransitionPage(child: ProfilePage()),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.callOutgoing,
      builder: (context, state) {
        final callId = int.tryParse(state.uri.queryParameters['callId'] ?? '');
        final callPrice =
            int.tryParse(state.uri.queryParameters['callPrice'] ?? '') ?? 0;
        return CallOutgoingPage(
          callId: callId,
          peerUserId: state.uri.queryParameters['peerUserId'] ?? '',
          peerName: state.uri.queryParameters['peerName'] ?? '',
          peerAvatar: state.uri.queryParameters['peerAvatar'],
          anchorId: state.uri.queryParameters['anchorId'],
          callPrice: callPrice,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.callIncoming,
      builder: (context, state) {
        final callId = int.tryParse(state.uri.queryParameters['callId'] ?? '');
        final leftSeconds =
            int.tryParse(state.uri.queryParameters['leftSeconds'] ?? '') ?? 30;
        if (callId == null || callId <= 0) {
          return Scaffold(
            appBar: AppBar(title: const Text('提示')),
            body: const Center(child: Text('来电参数无效，请返回重试')),
          );
        }
        return IncomingCallPage(
          callId: callId,
          peerUserId: state.uri.queryParameters['peerUserId'] ?? '',
          peerName: state.uri.queryParameters['peerName'] ?? '',
          peerAvatar: state.uri.queryParameters['peerAvatar'],
          leftSeconds: leftSeconds,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.callRoom,
      builder: (context, state) {
        final callId = int.tryParse(state.uri.queryParameters['callId'] ?? '');
        if (callId == null || callId <= 0) {
          return Scaffold(
            appBar: AppBar(title: const Text('提示')),
            body: const Center(child: Text('通话参数无效，请返回重试')),
          );
        }
        return CallRoomPage(
          callId: callId,
          peerUserId: state.uri.queryParameters['peerUserId'] ?? '',
          anchorId: state.uri.queryParameters['anchorId'],
          peerName: state.uri.queryParameters['peerName'] ?? '',
        );
      },
    ),
    GoRoute(
      path: AppRoutes.anchorDetail,
      builder: (context, state) {
        final anchor = AppRoutes.tryGetAnchorInfo(state.extra);
        final userId = int.tryParse(state.uri.queryParameters['userId'] ?? '');
        if (anchor == null) {
          if (userId != null && userId > 0) {
            return AnchorDetailPage(userId: userId);
          }
          return Scaffold(
            appBar: AppBar(title: const Text('提示')),
            body: const Center(child: Text('主播信息无效，请返回重试')),
          );
        }
        return AnchorDetailPage(anchor: anchor, userId: userId);
      },
    ),
    GoRoute(
      path: AppRoutes.userSearch,
      builder: (context, state) => const UserSearchPage(),
    ),
    GoRoute(
      path: AppRoutes.callHistory,
      builder: (context, state) => const CallPage(),
    ),
    GoRoute(
      path: AppRoutes.recharge,
      builder: (context, state) => const RechargePage(),
    ),
    GoRoute(
      path: AppRoutes.withdraw,
      builder: (context, state) => const WithdrawPage(),
    ),
    GoRoute(
      path: AppRoutes.withdrawAccount,
      builder: (context, state) => WithdrawAccountPage(
        initialAccount: state.extra is WithdrawAccount
            ? state.extra as WithdrawAccount
            : null,
      ),
    ),
    GoRoute(
      path: AppRoutes.coinTransactions,
      builder: (context, state) => const CoinTransactionsPage(),
    ),
    GoRoute(
      path: AppRoutes.diamondTransactions,
      builder: (context, state) => const DiamondTransactionsPage(),
    ),
    GoRoute(
      path: AppRoutes.editProfile,
      builder: (context, state) => const EditProfilePage(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: AppRoutes.settingsAgreement,
      builder: (context, state) => const AgreementPage(),
    ),
    GoRoute(
      path: AppRoutes.settingsPrivacy,
      builder: (context, state) => const PrivacyPage(),
    ),
    GoRoute(
      path: AppRoutes.settingsPassword,
      builder: (context, state) => const ChangePasswordPage(),
    ),
    GoRoute(
      path: AppRoutes.anchorApply,
      builder: (context, state) => const AnchorApplyPage(),
    ),
    GoRoute(
      path: '${AppRoutes.im}/:userId',
      builder: (context, state) {
        final peer = state.pathParameters['userId']!;
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : null;
        return ImPage(
          userId: peer,
          initialPeerNickname: extra?['peerNickname'] as String?,
          initialPeerAvatarUrl: extra?['peerAvatarUrl'] as String?,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.myMoments,
      builder: (context, state) => const MyMomentsPage(),
    ),
    GoRoute(
      path: AppRoutes.myFollowing,
      builder: (context, state) => const MyFollowingPage(),
    ),
    GoRoute(
      path: AppRoutes.myFans,
      builder: (context, state) => const MyFansPage(),
    ),
    GoRoute(
      path: AppRoutes.publishMoment,
      builder: (context, state) => const PublishMomentPage(),
    ),
    GoRoute(
      path: AppRoutes.giftPanel,
      builder: (context, state) => GiftPanel(
        anchorId: state.uri.queryParameters['anchorId'] ?? '',
        onClose: () => context.pop(),
      ),
    ),
  ],
);
