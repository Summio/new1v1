import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/system_notification_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../services/system_notification_service.dart';

class SystemNotificationDetailPage extends ConsumerStatefulWidget {
  final int notificationId;

  const SystemNotificationDetailPage({super.key, required this.notificationId});

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
      appBar: AppBar(title: const Text('系统通知')),
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
                  _typeLabel(detail.type),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatNotificationTime(detail.publishAt),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textHint,
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
