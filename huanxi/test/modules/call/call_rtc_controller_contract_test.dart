import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call rtc controller can release resources without notifying state', () {
    final text = File(
      'lib/modules/call/controllers/call_rtc_controller.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(text, contains('Future<void> leaveAndRelease({'));
    expect(text, contains('bool updateState = true'));
    expect(text, contains('unawaited(leaveAndRelease(updateState: false));'));
  });
}
