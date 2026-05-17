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
}
