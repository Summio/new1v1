import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../services/websocket_service.dart';
import 'main_shell.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  /// 本地"在线接单"状态（true=在线，false=手动离线）
  /// 由 Switch 控制，收到 presence 广播时同步
  bool _anchorOnline = true;
  StreamSubscription<PresenceEvent>? _presenceSub;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initPresenceListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(authProvider.notifier).fetchUserInfo();
    });
  }

  void _initPresenceListener() {
    _presenceSub = MainShell.presenceStream.listen((event) {
      if (!mounted) return;
      if (event.userId == _currentUserId) {
        setState(() {
          _anchorOnline = event.online;
        });
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  void _onOnlineStatusChanged(bool value) {
    // value: true=在线，false=手动离线
    WsService.instance.sendSetOnlineStatus(value);
    setState(() {
      _anchorOnline = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final isAnchor = authState.appRole == 'anchor';

    // 同步当前用户 ID
    if (_currentUserId != authState.userId) {
      _currentUserId = authState.userId;
    }

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
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                            image: authState.avatar != null
                                ? DecorationImage(image: NetworkImage(authState.avatar!), fit: BoxFit.cover)
                                : null,
                          ),
                          child: authState.avatar == null
                              ? const Icon(Icons.person, size: 40, color: AppTheme.primaryColor)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      authState.username ?? '未设置昵称',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    if (isAnchor) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.secondaryColor, borderRadius: BorderRadius.circular(8)),
                        child: const Text('认证主播', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${authState.userId ?? '-'}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.settings_outlined, color: AppTheme.textPrimary), onPressed: () => context.push(AppRoutes.settings)),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: AppTheme.balanceGradient, borderRadius: BorderRadius.circular(24), boxShadow: AppTheme.elevatedShadow),
              child: isAnchor
                  ? _buildAnchorBalance(authState, tokenNames)
                  : _buildUserBalance(authState, tokenNames, context),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: AppTheme.cardShadow),
              child: Column(
                children: [
                  _buildMenuTile(icon: Icons.currency_exchange_rounded, title: '充值', iconColor: const Color(0xFFFF9500), onTap: () => context.push(AppRoutes.recharge)),
                  _buildMenuTile(icon: Icons.history_rounded, title: '通话记录', iconColor: const Color(0xFF5856D6), onTap: () {}),
                  _buildMenuTile(icon: Icons.favorite_rounded, title: '我的关注', iconColor: const Color(0xFFFF2D55), onTap: () {}),
                  if (!isAnchor)
                    _buildMenuTile(icon: Icons.live_tv_rounded, title: '申请成为主播', iconColor: AppTheme.secondaryColor, onTap: () => context.push(AppRoutes.anchorApply)),
                  if (isAnchor)
                    _buildMenuTile(
                      icon: Icons.online_prediction_rounded,
                      title: '在线接单',
                      iconColor: const Color(0xFF34C759),
                      onTap: () {},
                      trailing: Switch(
                        value: _anchorOnline,
                        onChanged: _onOnlineStatusChanged,
                        activeThumbColor: AppTheme.primaryColor,
                        activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                  _buildMenuTile(icon: Icons.account_balance_wallet_rounded, title: '我的钱包', iconColor: const Color(0xFFFF9500), onTap: () => context.push(AppRoutes.wallet)),
                  _buildMenuTile(icon: Icons.auto_awesome, title: '美颜设置', iconColor: const Color(0xFFFF6B9D), onTap: () => context.push(AppRoutes.beautySettings)),
                  _buildMenuTile(icon: Icons.shield_rounded, title: '安全中心', iconColor: const Color(0xFF34C759), onTap: () => context.push(AppRoutes.settingsPassword), isLast: true),
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
                style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('退出登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildUserBalance(AuthState authState, TokenNamesState tokenNames, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('${tokenNames.coinName}余额', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.recharge),
                    child: Text(authState.coins.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('${tokenNames.diamondName}余额', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.wallet),
                    child: Text(authState.diamonds.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnchorBalance(AuthState authState, TokenNamesState tokenNames) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('累计收益 (元)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text((authState.coins / 100).toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('${tokenNames.diamondName}余额', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(authState.diamonds.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, required Color iconColor, required VoidCallback onTap, bool isLast = false, Widget? trailing}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 20),
          onTap: onTap,
        ),
        if (!isLast) const Divider(indent: 64, endIndent: 20, height: 1, color: AppTheme.dividerColor),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) context.go(AppRoutes.login);
    }
  }
}
