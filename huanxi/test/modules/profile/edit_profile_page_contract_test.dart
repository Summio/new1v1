import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edit profile page no longer allows gender editing', () {
    final page = File(
      'lib/modules/profile/edit_profile_page.dart',
    ).readAsStringSync();

    expect(page, isNot(contains('String _gender')));
    expect(page, isNot(contains("'gender': _gender")));
    expect(page, isNot(contains('initialValue: _gender')));
    expect(page, isNot(contains('setState(() => _gender')));
    expect(page, contains('authState.gender'));
  });

  test('edit profile city picker uses a scrollable city list', () {
    final page = File(
      'lib/modules/profile/edit_profile_page.dart',
    ).readAsStringSync();

    expect(page, contains("'市'"));
    expect(page, contains('ListView.separated'));
    expect(page, contains('itemCount: cities.length'));
    expect(page, contains('selectedCity = city'));
    expect(page, contains('height: 200'));
    expect(page, contains('Formatters.locationCity(_locationCity)'));
    expect(
      page,
      isNot(contains("decoration: const InputDecoration(labelText: '市')")),
    );
  });
}
