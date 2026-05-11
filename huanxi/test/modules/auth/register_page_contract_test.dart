import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('register page defers gender selection to initial profile flow', () {
    final text = File('lib/modules/auth/register_page.dart').readAsStringSync();

    expect(text, isNot(contains('String? _gender')));
    expect(text, isNot(contains('请选择性别')));
    expect(text, isNot(contains("DropdownMenuItem(value: 'male'")));
    expect(text, isNot(contains("DropdownMenuItem(value: 'female'")));
    expect(text, contains("data: {'phone': phone, 'password': password}"));
    expect(text, contains("respData['initial_profile_completed'] == true"));
    expect(
      text,
      contains(
        'router.go(completed ? AppRoutes.index : AppRoutes.initialProfile)',
      ),
    );
    expect(text, isNot(contains("'gender': 'male'")));
  });
}
