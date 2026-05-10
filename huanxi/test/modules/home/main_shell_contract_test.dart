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
}
