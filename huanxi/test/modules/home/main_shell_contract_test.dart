import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main shell intercepts root back without exiting app', () {
    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();

    expect(shell, contains('BackButtonListener'));
    expect(shell, contains('PopScope'));
    expect(shell, contains('canPop: false'));
    expect(shell, contains('onPopInvokedWithResult'));
    expect(shell, contains('onBackButtonPressed'));
    expect(shell, contains('FocusScope.of(context).unfocus()'));
    expect(shell, isNot(contains('SystemNavigator.pop')));
    final backHandler = shell.split('Future<bool> _handleRootBackButtonPressed()').last;
    expect(
      backHandler.split('@override').first,
      isNot(contains('context.go(')),
    );
    expect(backHandler, contains('return true;'));
  });
}
