import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
      ref.read(appInitProvider.notifier).init();
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
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            authState.username ?? '未设置昵称',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildGenderChip(_genderText(authState.gender)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildAvailabilityChip(
                          label: _availabilityText(authState),
                          color: _availabilityColor(authState),
                        ),
                        if (isCertifiedUser) ...[
                          const SizedBox(width: 6),
                          _buildCertificationChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID: ${authState.userId ?? '-'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (authState.userId != null) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            key: const ValueKey('profile_user_id_copy_button'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _copyUserId(authState.userId!),
                            child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
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
                    icon: Icons.do_not_disturb_on_outlined,
                    title: '勿扰模式',
                    iconColor: const Color(0xFF007AFF),
                    onTap: () => context.push(AppRoutes.doNotDisturb),
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

  Widget _buildGenderChip(String genderText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        genderText,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildAvailabilityChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('●', style: TextStyle(color: color, fontSize: 9, height: 1)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificationChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '真人认证',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  String _genderText(String gender) {
    return gender == 'female' ? '女' : '男';
  }

  String _availabilityText(AuthState authState) {
    return authState.videoDndEnabled ? '勿扰' : '在线';
  }

  Color _availabilityColor(AuthState authState) {
    return authState.videoDndEnabled
        ? const Color(0xFFAF52DE)
        : AppTheme.onlineGreen;
  }

  Future<void> _copyUserId(int userId) async {
    await Clipboard.setData(ClipboardData(text: userId.toString()));
    if (!mounted) return;
    AppToast.showSnackBar(context, const SnackBar(content: Text('ID已复制')));
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
}
