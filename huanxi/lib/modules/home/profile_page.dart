import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
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
    final tokenNames = ref.watch(tokenNamesProvider);
    final isCertifiedUser = authState.isCertifiedUser;

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
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.editProfile),
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
                    icon: Icons.verified_user_rounded,
                    title: '认证中心',
                    iconColor: AppTheme.secondaryColor,
                    onTap: () => context.push(AppRoutes.certificationCenter),
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
