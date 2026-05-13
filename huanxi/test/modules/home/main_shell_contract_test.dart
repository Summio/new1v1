import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main shell does not intercept system back', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, isNot(contains('PopScope')));
    expect(shell, isNot(contains('canPop: false')));
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
