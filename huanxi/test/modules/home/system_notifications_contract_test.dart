import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system notification routes endpoints and pages are registered', () {
    final endpoints = File(
      'lib/core/constants/api_endpoints.dart',
    ).readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    final messages = File(
      'lib/modules/home/messages_page.dart',
    ).readAsStringSync();
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();
    final service = File(
      'lib/services/system_notification_service.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/app/providers/system_notification_provider.dart',
    ).readAsStringSync();
    final listPage = File(
      'lib/modules/home/system_notifications_page.dart',
    ).readAsStringSync();
    final detailPage = File(
      'lib/modules/home/system_notification_detail_page.dart',
    ).readAsStringSync();

    expect(endpoints, contains('systemNotifications'));
    expect(endpoints, contains('app/notifications'));
    expect(endpoints, isNot(contains('systemNotificationUnreadCount')));
    expect(endpoints, isNot(contains('app/notifications/unread-count')));
    expect(endpoints, contains('systemNotificationReadAll'));

    expect(router, contains('AppRoutes.systemNotifications'));
    expect(router, contains("'/notifications'"));
    expect(router, contains('SystemNotificationsPage'));
    expect(router, contains('SystemNotificationDetailPage'));
    final shellMatch = RegExp(
      r'ShellRoute\([\s\S]*?\],\s*\),',
      multiLine: true,
    ).firstMatch(router);
    expect(shellMatch, isNotNull);
    final shellSection = shellMatch!.group(0)!;
    expect(
      shellSection,
      isNot(contains('path: AppRoutes.systemNotifications')),
      reason: '系统通知列表页应该是独立二级页，不应挂在带底部导航的 ShellRoute 内',
    );

    expect(service, contains('SystemNotificationService'));
    expect(service, isNot(contains('fetchUnreadSummary')));
    expect(service, isNot(contains('SystemNotificationUnreadSummary')));
    expect(service, contains('markRead'));
    expect(service, contains('markUnread'));
    expect(service, contains('readAll'));

    expect(provider, isNot(contains('systemNotificationUnreadProvider')));
    expect(provider, isNot(contains('SystemNotificationUnreadNotifier')));
    expect(provider, contains('SystemNotificationListNotifier'));

    expect(messages, contains('系统通知'));
    expect(messages, contains('_SystemNotificationEntryCard'));
    expect(messages, isNot(contains('systemNotificationUnreadProvider')));
    expect(messages, isNot(contains('_NotificationBadge')));
    expect(messages, contains('AppRoutes.systemNotifications'));

    expect(shell, isNot(contains('_systemNotificationUnreadCount')));
    expect(
      shell,
      isNot(contains('_imUnreadCount + _systemNotificationUnreadCount')),
    );
    expect(shell, isNot(contains('system_notification_unread_changed')));
    expect(shell, isNot(contains('system_popup_pending')));
    expect(shell, isNot(contains('_handleSystemPopupPending')));
    expect(shell, contains('fetchStartupSystemPopups'));

    expect(listPage, contains('暂无系统通知'));
    expect(listPage, contains('PopupMenuButton'));
    expect(listPage, contains('标记未读'));
    expect(listPage, contains('标记已读'));
    expect(listPage, contains('全部已读'));
    expect(listPage, contains('_typeLabel'));
    expect(listPage, contains('_formatNotificationTime'));
    expect(
      listPage,
      isNot(contains(r'${_typeLabel(item.type)} · ${item.publishAt}')),
    );
    expect(listPage, isNot(contains('删除')));
    expect(detailPage, contains('SystemNotificationDetailPage'));
    expect(detailPage, contains('systemNotificationListProvider'));
    expect(detailPage, isNot(contains('systemNotificationUnreadProvider')));
    expect(detailPage, contains('SelectableText'));
    expect(detailPage, contains('_formatNotificationTime'));
    expect(detailPage, contains('_formatNotificationTime(detail.publishAt)'));
  });
}
