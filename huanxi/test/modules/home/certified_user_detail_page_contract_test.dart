import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('certified user detail page formats location as city only', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(page, contains('Formatters.locationCity(value)'));
    expect(page, contains('_locationLabel(certifiedUser.locationCity)'));
    expect(page, contains("return city.isEmpty ? '所在地未填' : city;"));
  });

  test('certified user detail keeps backend album order', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(page, contains('for (final item in certifiedUser.albumPhotos)'));
    expect(page, isNot(contains('photos.sort')));
    expect(page, isNot(contains('..sort')));
  });
}
