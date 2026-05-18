import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/do_not_disturb_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';

class DoNotDisturbPage extends ConsumerStatefulWidget {
  const DoNotDisturbPage({super.key});

  @override
  ConsumerState<DoNotDisturbPage> createState() => _DoNotDisturbPageState();
}

class _DoNotDisturbPageState extends ConsumerState<DoNotDisturbPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(doNotDisturbProvider.notifier).load();
    });
  }

  Future<void> _update(DoNotDisturbSettings next) async {
    final notifier = ref.read(doNotDisturbProvider.notifier);
    final previous = ref.read(doNotDisturbProvider).settings;
    try {
      await notifier.update(next, previous: previous);
    } catch (_) {
      notifier.rollback(previous);
      if (mounted) {
        AppToast.showSnackBar(
          context,
          const SnackBar(content: Text('勿扰设置保存失败，请稍后重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(doNotDisturbProvider);
    final settings = state.settings;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        centerTitle: true,
        title: const Text('勿扰模式'),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _DndSwitchTile(
                  icon: Icons.chat_bubble_outline,
                  title: '文字勿扰',
                  subtitle: '开启后不接收文字消息',
                  value: settings.textDndEnabled,
                  enabled: !state.isSaving,
                  onChanged: (value) =>
                      _update(settings.copyWith(textDndEnabled: value)),
                ),
                _DndSwitchTile(
                  icon: Icons.videocam_outlined,
                  title: '视频勿扰',
                  subtitle: '开启后不接收视频通话',
                  value: settings.videoDndEnabled,
                  enabled: !state.isSaving,
                  onChanged: (value) =>
                      _update(settings.copyWith(videoDndEnabled: value)),
                ),
                _DndSwitchTile(
                  icon: Icons.visibility_off_outlined,
                  title: '榜单隐身',
                  subtitle: '开启后不参与排行榜',
                  value: settings.rankingInvisibleEnabled,
                  enabled: !state.isSaving,
                  onChanged: (value) => _update(
                    settings.copyWith(rankingInvisibleEnabled: value),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DndSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _DndSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        value: value,
        activeThumbColor: AppTheme.primaryColor,
        activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.4),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
