import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main shell disables system back while bottom navigation is visible', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('PopScope'));
    expect(shell, contains('canPop: false'));
    expect(shell, isNot(contains('BackButtonListener')));
    expect(shell, isNot(contains('ModalRoute.of(context)?.isCurrent')));
    expect(shell, isNot(contains('SystemNavigator.pop')));
  });
}
