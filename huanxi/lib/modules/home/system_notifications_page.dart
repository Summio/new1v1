import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/system_notification_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../services/system_notification_service.dart';

class SystemNotificationsPage extends ConsumerStatefulWidget {
  const SystemNotificationsPage({super.key});

  @override
  ConsumerState<SystemNotificationsPage> createState() =>
      _SystemNotificationsPageState();
}

class _SystemNotificationsPageState
    extends ConsumerState<SystemNotificationsPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(systemNotificationListProvider.notifier).refresh();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      ref.read(systemNotificationListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(systemNotificationListProvider);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('系统通知'),
        actions: [
          TextButton(
            onPressed: state.items.isEmpty
                ? null
                : () => ref
                      .read(systemNotificationListProvider.notifier)
                      .readAll(),
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: state.isLoading
          ? StatusView.loading()
          : state.error != null
          ? StatusView.error(
              message: state.error!,
              onRetry: () =>
                  ref.read(systemNotificationListProvider.notifier).refresh(),
            )
          : state.items.isEmpty
          ? StatusView.empty(message: '暂无系统通知')
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(systemNotificationListProvider.notifier).refresh(),
              child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  if (index >= state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    );
                  }
                  final item = state.items[index];
                  return _NotificationTile(item: item);
                },
              ),
            ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final SystemNotificationItem item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconData = _typeIcon(item.type);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
            child: Icon(iconData, color: AppTheme.primaryColor),
          ),
          if (!item.isRead)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _typeLabel(item.type),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.content.isEmpty ? '暂无内容' : item.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: AppTheme.textPrimary,
              fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatNotificationTime(item.publishAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'read') {
            ref.read(systemNotificationListProvider.notifier).markRead(item.id);
          } else if (value == 'unread') {
            ref
                .read(systemNotificationListProvider.notifier)
                .markUnread(item.id);
          }
        },
        itemBuilder: (context) => [
          if (!item.isRead)
            const PopupMenuItem(value: 'read', child: Text('标记已读')),
          if (item.isRead)
            const PopupMenuItem(value: 'unread', child: Text('标记未读')),
        ],
      ),
      onTap: () async {
        await context.push('${AppRoutes.systemNotifications}/${item.id}');
        if (!context.mounted) return;
        ref.read(systemNotificationListProvider.notifier).refresh();
      },
    );
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'account':
      return Icons.account_balance_wallet_outlined;
    case 'review':
      return Icons.fact_check_outlined;
    case 'interaction':
      return Icons.favorite_border_rounded;
    case 'announcement':
    default:
      return Icons.campaign_outlined;
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'account':
      return '账户通知';
    case 'review':
      return '审核通知';
    case 'interaction':
      return '互动通知';
    case 'announcement':
    default:
      return '平台公告';
  }
}

String _formatNotificationTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '-';
  final now = DateTime.now();
  final diff = now.difference(parsed);
  if (!diff.isNegative) {
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
  }

  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  if (parsed.year == now.year) {
    return '$month-$day $hour:$minute';
  }
  return '${parsed.year}-$month-$day $hour:$minute';
}
