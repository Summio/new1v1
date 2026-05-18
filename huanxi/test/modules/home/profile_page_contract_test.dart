import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile header shows certification text gender and online status', () {
    final page = File('lib/modules/home/profile_page.dart').readAsStringSync();

    expect(page, contains("'真人认证'"));
    expect(page, isNot(contains("'已真人认证'")));
    expect(page, contains('_genderText(authState.gender)'));
    expect(page, contains('_availabilityText(authState)'));
    expect(page, contains('authState.videoDndEnabled'));
    expect(page, contains("'在线'"));
    expect(page, contains("'勿扰'"));
  });
}
