import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discover page exposes moment feed categories', () {
    final discoverText = File(
      'lib/modules/home/discover_page.dart',
    ).readAsStringSync();
    final providerText = File(
      'lib/app/providers/moment_provider.dart',
    ).readAsStringSync();

    expect(providerText.indexOf('最近'), lessThan(providerText.indexOf('推荐')));
    expect(providerText.indexOf('推荐'), lessThan(providerText.indexOf('关注')));
    expect(providerText, contains("recommend('recommend', '推荐'"));
    expect(discoverText, contains('MomentFeedCategory.latest'));
    expect(discoverText, contains('MomentFeedCategory.values'));
    expect(discoverText, contains('momentFeedProvider('));
  });

  test('discover restores and writes remembered tab selections', () {
    final discoverText = File(
      'lib/modules/home/discover_page.dart',
    ).readAsStringSync();

    expect(discoverText, contains('mainTabMemoryProvider'));
    expect(discoverText, contains('discoverTabIndex'));
    expect(discoverText, contains('setDiscoverTabIndex'));
    expect(discoverText, contains('discoverMomentCategory'));
    expect(discoverText, contains('setDiscoverMomentCategory'));
  });

  test('moment list view supports category-specific empty text', () {
    final text = File(
      'lib/modules/home/moment_list_view.dart',
    ).readAsStringSync();

    expect(text, contains('emptyTitle'));
    expect(text, contains('emptySubtitle'));
  });

  test('moment card only shows moment time below nickname', () {
    final text = File('lib/modules/home/moment_card.dart').readAsStringSync();

    expect(text, contains('_formatTime(moment.createdAt)'));
    expect(text, isNot(contains('_formatDate(moment.createdAt)')));
    expect(text, isNot(contains('String _formatDate')));
  });
}
