import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/system_notification_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../services/system_notification_service.dart';

class SystemNotificationDetailPage extends ConsumerStatefulWidget {
  final int notificationId;

  const SystemNotificationDetailPage({
    super.key,
    required this.notificationId,
  });

  @override
  ConsumerState<SystemNotificationDetailPage> createState() =>
      _SystemNotificationDetailPageState();
}

class _SystemNotificationDetailPageState
    extends ConsumerState<SystemNotificationDetailPage> {
  late Future<SystemNotificationDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SystemNotificationDetail> _load() async {
    final detail = await SystemNotificationService.instance.fetchDetail(
      widget.notificationId,
    );
    await ref.read(systemNotificationUnreadProvider.notifier).refresh();
    return detail;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('通知详情')),
      body: FutureBuilder<SystemNotificationDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return StatusView.loading();
          }
          if (snapshot.hasError) {
            return StatusView.error(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _future = _load();
                });
              },
            );
          }
          final detail = snapshot.data;
          if (detail == null) {
            return StatusView.empty(message: '通知不存在');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _typeIcon(detail.type),
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _typeLabel(detail.type),
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        detail.publishAt,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppTheme.textHint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: SelectableText(
                    detail.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.7,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
