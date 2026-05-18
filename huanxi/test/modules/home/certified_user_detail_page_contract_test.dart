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

  test('certified user detail colors male gender tag blue', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(page, contains('_genderColor(certifiedUser.gender)'));
    expect(page, contains("value == 'male' ? AppTheme.primaryColor"));
    expect(page, contains('const Color(0xFFFF69B4)'));
  });

  test('certified user detail shows profile facts as top tags', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(page, contains('_buildPrimaryProfileTags('));
    expect(page, contains('_buildSecondaryProfileTags('));
    expect(page, contains("'身高未填'"));
    expect(page, contains("'体重未填'"));
    expect(page, contains('_locationLabel(certifiedUser.locationCity)'));
    expect(page, isNot(contains('_buildInfoChip(')));
  });

  test(
    'certified user detail lays out avatar and certification in identity row',
    () {
      final page = File(
        'lib/modules/home/certified_user_detail_page.dart',
      ).readAsStringSync();

      expect(page, contains('_buildProfileAvatar(certifiedUser)'));
      expect(page, contains('_buildCertificationStatusChip()'));
      expect(page, contains('certified_detail_identity_status_row'));
      expect(page, contains('certifiedUser.isCertifiedUser'));
      expect(page, contains('CircleAvatar'));
      expect(page, contains("'真人'"));
      expect(page, isNot(contains("'真人认证'")));
    },
  );

  test('certified user detail profile tags stay compact in wraps', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    final tagBuilderStart = page.indexOf('Widget _buildTag({');
    final tagBuilderEnd = page.indexOf('List<Widget> _buildPrimaryProfileTags');
    final tagBuilder = page.substring(tagBuilderStart, tagBuilderEnd);

    expect(tagBuilder, contains('mainAxisSize: MainAxisSize.min'));
    expect(tagBuilder, contains('maxLines: 1'));
    expect(tagBuilder, contains('overflow: TextOverflow.ellipsis'));
  });
}
