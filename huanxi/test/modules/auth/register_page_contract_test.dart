import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'register page requires explicit gender selection and submits chosen gender',
    () {
      final text = File(
        'lib/modules/auth/register_page.dart',
      ).readAsStringSync();

      expect(text, contains('String? _gender'));
      expect(text, contains('请选择性别'));
      expect(text, contains("DropdownMenuItem(value: 'male'"));
      expect(text, contains("DropdownMenuItem(value: 'female'"));
      expect(text, contains("'gender': _gender"));
      expect(text, isNot(contains("'gender': 'male'")));
    },
  );
}
