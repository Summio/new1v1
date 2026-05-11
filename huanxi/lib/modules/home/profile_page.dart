import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/capability_limit_guard.dart';
import '../../core/utils/app_toast.dart';
import '../../services/review_entry_guard_service.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _isCheckingProfileEdit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(authProvider.notifier).fetchUserInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final appInitState = ref.watch(appInitProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final isCertifiedUser = authState.isCertifiedUser;
    final customerServiceEnabled =
        appInitState.customerServiceEnabled &&
        (appInitState.customerServiceUserId?.trim().isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF0F7FF), Colors.white],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: _openEditProfile,
                          child: Hero(
                            tag: 'user_avatar',
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                  ),
                                ],
                                image: authState.avatar != null
                                    ? DecorationImage(
                                        image: NetworkImage(authState.avatar!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: authState.avatar == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: AppTheme.primaryColor,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openEditProfile,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.edit,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      authState.username ?? '未设置昵称',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isCertifiedUser) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '已真人认证',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${authState.userId ?? '-'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: AppTheme.textPrimary,
                ),
                onPressed: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.balanceGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.elevatedShadow,
              ),
              child: _buildUserBalance(authState, tokenNames, context),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                children: [
                  _buildMenuTile(
                    icon: Icons.headset_mic_outlined,
                    title: '在线客服',
                    iconColor: customerServiceEnabled
                        ? AppTheme.primaryColor
                        : AppTheme.textHint,
                    onTap: () => _openCustomerService(context, ref),
                  ),
                  _buildMenuTile(
                    icon: Icons.feedback_outlined,
                    title: '意见反馈',
                    iconColor: AppTheme.secondaryColor,
                    onTap: () => context.push(AppRoutes.feedback),
                  ),
                  _buildMenuTile(
                    icon: Icons.verified_user_rounded,
                    title: '认证中心',
                    iconColor: AppTheme.secondaryColor,
                    onTap: () => _openCertificationCenter(context, ref),
                  ),
                  _buildMenuTile(
                    icon: Icons.dynamic_feed_rounded,
                    title: '我的动态',
                    iconColor: const Color(0xFF5856D6),
                    onTap: () => context.push(AppRoutes.myMoments),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: () => _handleLogout(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  '退出登录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildUserBalance(
    AuthState authState,
    TokenNamesState tokenNames,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${tokenNames.coinName}余额',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.recharge),
                    child: Text(
                      authState.coins.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${tokenNames.diamondName}余额',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.withdraw),
                    child: Text(
                      authState.diamonds.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openEditProfile() async {
    if (_isCheckingProfileEdit) return;
    setState(() {
      _isCheckingProfileEdit = true;
    });
    try {
      await ref.read(appInitProvider.notifier).init();
      if (!mounted) return;

      final authState = ref.read(authProvider);
      final initState = ref.read(appInitProvider);
      final capabilityMessage = profileEditRestrictionMessage(
        authState,
        initState,
      );
      if (capabilityMessage != null) {
        AppToast.show(context, capabilityMessage);
        return;
      }

      final entryStatus = await ReviewEntryGuardService.instance
          .fetchEntryStatus();
      if (!mounted) return;
      final profileEdit = entryStatus.profileEdit;
      if (!profileEdit.canEnter) {
        AppToast.show(context, profileEdit.msg);
        return;
      }
      context.push(AppRoutes.editProfile);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, '状态检查失败，请稍后再试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingProfileEdit = false;
        });
      }
    }
  }

  Future<void> _openCertificationCenter(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(appInitProvider.notifier).init();
    if (!context.mounted) return;

    final authState = ref.read(authProvider);
    final initState = ref.read(appInitProvider);
    final message = certificationEntryRestrictionMessage(authState, initState);
    if (message != null) {
      AppToast.show(context, message);
      return;
    }

    await context.push(AppRoutes.certificationCenter);
  }

  Future<void> _openCustomerService(BuildContext context, WidgetRef ref) async {
    await ref.read(appInitProvider.notifier).init();
    if (!context.mounted) return;
    final initState = ref.read(appInitProvider);
    final userId = initState.customerServiceUserId?.trim() ?? '';
    if (!initState.customerServiceEnabled || userId.isEmpty) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('客服暂未配置，请稍后再试')),
      );
      return;
    }
    await context.push(
      '${AppRoutes.im}/$userId',
      extra: {
        'peerNickname': initState.customerServiceNickname,
        'peerAvatarUrl': initState.customerServiceAvatar,
        'isCustomerService': true,
      },
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required Color iconColor,
    required VoidCallback onTap,
    bool isLast = false,
    Widget? trailing,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          trailing:
              trailing ??
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textHint,
                size: 20,
              ),
          onTap: onTap,
        ),
        if (!isLast)
          const Divider(
            indent: 64,
            endIndent: 20,
            height: 1,
            color: AppTheme.dividerColor,
          ),
      ],
    );
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go(AppRoutes.login);
    }
  }
}
