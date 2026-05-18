import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/permissions/mandatory_permission_service.dart';
import '../../services/teen_mode_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _keepAliveReady = false;
  bool _keepAliveBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshKeepAliveState();
  }

  Future<void> _refreshKeepAliveState() async {
    final service = MandatoryPermissionService.instance;
    final preferenceEnabled = service.keepAlivePreferenceEnabled;
    await service.check();
    if (!mounted) return;
    setState(() {
      _keepAliveReady = preferenceEnabled;
    });
  }

  Future<void> _ensureKeepAlive(bool value) async {
    if (_keepAliveBusy) return;
    setState(() {
      _keepAliveBusy = true;
    });
    try {
      if (value) {
        final state = await MandatoryPermissionService.instance
            .startKeepAliveForLoggedInUser();
        if (!state.requiredGranted && mounted) {
          context.go(AppRoutes.mandatoryPermissions);
          return;
        }
      } else {
        await MandatoryPermissionService.instance.stopKeepAliveByUser();
      }
      await _refreshKeepAliveState();
    } finally {
      if (mounted) {
        setState(() {
          _keepAliveBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        centerTitle: true,
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          const _SectionTitle(title: '账号'),
          _SettingsTile(
            icon: Icons.person_outline,
            title: '账号与安全',
            onTap: () => context.push(AppRoutes.settingsPassword),
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: '后台保持在线',
            onTap: _keepAliveBusy
                ? null
                : () => _ensureKeepAlive(!_keepAliveReady),
            trailing: Switch(
              value: _keepAliveReady,
              onChanged: _keepAliveBusy ? null : _ensureKeepAlive,
              activeThumbColor: AppTheme.primaryColor,
              activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionTitle(title: '隐私与安全'),
          _SettingsTile(
            icon: Icons.child_care,
            title: '青少年模式',
            onTap: () async {
              if (TeenModeService.instance.isLocked) {
                context.go(AppRoutes.teenModeVerify);
                return;
              }
              final enabled = await context.push<bool>(AppRoutes.teenModeSetup);
              if (enabled == true && context.mounted) {
                context.go(AppRoutes.teenModeVerify);
              }
            },
          ),
          const SizedBox(height: 8),
          const _SectionTitle(title: '其他'),
          _SettingsTile(
            icon: Icons.language,
            title: '语言',
            trailing: const Text(
              '简体中文',
              style: TextStyle(color: AppTheme.textHint, fontSize: 14),
            ),
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: '关于我们',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: '欢喜',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2026 欢喜科技',
              );
            },
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: '用户协议',
            onTap: () => context.push(AppRoutes.settingsAgreement),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: '隐私政策',
            onTap: () => context.push(AppRoutes.settingsPrivacy),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow,
              ),
              child: OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('确定要退出当前账号吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('退出'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) {
                      context.go(AppRoutes.login);
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  side: const BorderSide(color: AppTheme.errorColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('退出登录'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '欢喜 v1.0.0 | ${authState.userId != null ? 'ID: ${authState.userId}' : ''}',
              style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          color: AppTheme.textHint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
        trailing:
            trailing ??
            const Icon(Icons.chevron_right, color: AppTheme.textHint),
        onTap: onTap,
      ),
    );
  }
}
