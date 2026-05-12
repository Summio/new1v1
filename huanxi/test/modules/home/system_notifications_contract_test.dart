import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system notification routes endpoints and pages are registered', () {
    final endpoints = File('lib/core/constants/api_endpoints.dart').readAsStringSync();
    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    final messages = File('lib/modules/home/messages_page.dart').readAsStringSync();
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();
    final service = File('lib/services/system_notification_service.dart').readAsStringSync();
    final provider = File('lib/app/providers/system_notification_provider.dart').readAsStringSync();
    final listPage = File('lib/modules/home/system_notifications_page.dart').readAsStringSync();
    final detailPage = File('lib/modules/home/system_notification_detail_page.dart').readAsStringSync();

    expect(endpoints, contains('systemNotifications'));
    expect(endpoints, contains('app/notifications'));
    expect(endpoints, contains('systemNotificationUnreadCount'));
    expect(endpoints, contains('app/notifications/unread-count'));
    expect(endpoints, contains('systemNotificationReadAll'));

    expect(router, contains('AppRoutes.systemNotifications'));
    expect(router, contains("'/notifications'"));
    expect(router, contains('SystemNotificationsPage'));
    expect(router, contains('SystemNotificationDetailPage'));

    expect(service, contains('SystemNotificationService'));
    expect(service, contains('fetchUnreadSummary'));
    expect(service, contains('markRead'));
    expect(service, contains('markUnread'));
    expect(service, contains('readAll'));

    expect(provider, contains('systemNotificationUnreadProvider'));
    expect(provider, contains('SystemNotificationListNotifier'));

    expect(messages, contains('系统通知'));
    expect(messages, contains('_SystemNotificationEntryCard'));
    expect(messages, contains('systemNotificationUnreadProvider'));
    expect(messages, contains('AppRoutes.systemNotifications'));

    expect(shell, contains('_systemNotificationUnreadCount'));
    expect(shell, contains('_imUnreadCount + _systemNotificationUnreadCount'));
    expect(shell, contains('system_notification_unread_changed'));

    expect(listPage, contains('暂无系统通知'));
    expect(listPage, contains('标记未读'));
    expect(listPage, contains('全部已读'));
    expect(listPage, isNot(contains('删除')));
    expect(detailPage, contains('SystemNotificationDetailPage'));
    expect(detailPage, contains('SelectableText'));
  });
}
