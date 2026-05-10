import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edit profile page uses a shared china location data source', () {
    final page = File(
      'lib/modules/profile/edit_profile_page.dart',
    ).readAsStringSync();

    expect(page, contains('chinaProvinceCityMap'));
    expect(page, isNot(contains('const cityMap = <String, List<String>>{')));
    expect(page, contains("选择所在地（到市/州/盟/地区）"));
    expect(page, contains("市/州/盟/地区"));
  });

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

  test('edit profile album supports moving photos and mixed review prompt', () {
    final page = File(
      'lib/modules/profile/edit_profile_page.dart',
    ).readAsStringSync();

    expect(page, contains('void _moveAlbumPhoto(int index, int delta)'));
    expect(page, contains('_moveAlbumPhoto(index, -1)'));
    expect(page, contains('_moveAlbumPhoto(index, 1)'));
    expect(page, contains('Icons.arrow_upward'));
    expect(page, contains('Icons.arrow_downward'));
    expect(page, contains('资料已保存，部分修改已提交审核'));
  });

  test(
    'edit profile entry checks review status before navigation and render',
    () {
      final profilePage = File(
        'lib/modules/home/profile_page.dart',
      ).readAsStringSync();
      final editPage = File(
        'lib/modules/profile/edit_profile_page.dart',
      ).readAsStringSync();
      final service = File(
        'lib/services/review_entry_guard_service.dart',
      ).readAsStringSync();

      expect(service, contains('reviewEntryStatus'));
      expect(service, contains('reasonCode'));
      expect(profilePage, contains('fetchEntryStatus'));
      expect(profilePage, contains('profileEdit.canEnter'));
      expect(profilePage, contains('状态检查失败，请稍后再试'));
      expect(editPage, contains('_isEntryChecking'));
      expect(editPage, contains('CircularProgressIndicator'));
      expect(editPage, contains('profileEdit.canEnter'));
      expect(editPage, contains('AppRoutes.profile'));
    },
  );
}
