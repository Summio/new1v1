import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main shell intercepts system back on first-level tabs only', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('PopScope'));
    expect(shell, contains('canPop: !_shouldBlockRootBack(currentLocation)'));
    expect(shell, contains('bool _shouldBlockRootBack(String location)'));
    expect(shell, contains('location == AppRoutes.index'));
    expect(shell, contains('location == AppRoutes.discover'));
    expect(shell, contains('location == AppRoutes.messages'));
    expect(shell, contains('location == AppRoutes.profile'));
    expect(shell, isNot(contains('startsWith(AppRoutes.profile) &&')));
    expect(shell, isNot(contains('BackButtonListener')));
    expect(shell, isNot(contains('ModalRoute.of(context)?.isCurrent')));
    expect(shell, isNot(contains('SystemNavigator.pop')));
  });

  test('main shell keeps bottom tab routes free of remembered query state', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('context.go(AppRoutes.index)'));
    expect(shell, contains('context.go(AppRoutes.discover)'));
    expect(shell, contains('context.go(AppRoutes.messages)'));
    expect(shell, isNot(contains("tab='")));
    expect(shell, isNot(contains('relation=')));
  });

  test('main shell polls system popups over http without websocket popup events', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('fetchPendingPopups'));
    expect(shell, isNot(contains('system_popup_pending')));
    expect(shell, isNot(contains('_handleSystemPopupPending')));
  });

  test('main shell starts and stops popup polling with lifecycle', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('Timer.periodic'));
    expect(shell, contains('fetchPendingPopups'));
    expect(shell, contains('AppLifecycleState.resumed'));
    expect(shell, contains('AppLifecycleState.paused'));
    expect(shell, contains('AppLifecycleState.inactive'));
    expect(shell, contains('cancel'));
  });

  test('main shell only suppresses popup after successful ack and startup can retry', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();
    final showPopupStart = shell.indexOf(
      'Future<bool> _showSystemPopupIfAllowed',
    );
    final showPopupEnd = shell.indexOf('int _getCurrentIndex', showPopupStart);
    final startupFetchStart = shell.indexOf(
      'Future<void> _fetchStartupSystemPopups',
    );
    final startupFetchEnd = shell.indexOf(
      'Future<void> _fetchPendingSystemPopups',
      startupFetchStart,
    );
    final showPopup = shell.substring(showPopupStart, showPopupEnd);
    final startupFetch = shell.substring(startupFetchStart, startupFetchEnd);

    expect(
      showPopup.indexOf('_handledSystemPopupIds.add(popup.id)'),
      greaterThan(showPopup.indexOf('await _systemPopupService.ackPopup(popup.id)')),
    );
    expect(
      startupFetch.indexOf('_startupSystemPopupsRequested = true'),
      greaterThan(startupFetch.indexOf('final handled = await _showSystemPopupIfAllowed(popup)')),
    );
    expect(startupFetch, contains('if (allPopupsHandled)'));
    expect(showPopup, contains('Future<bool> _showSystemPopupIfAllowed'));
    expect(showPopup, contains('return false;'));
  });
}
