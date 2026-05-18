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
    expect(providerText, contains("latest('latest', '最近'"));
    expect(providerText, contains("recommend('recommend', '推荐'"));
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

  test('discover sub categories support swipe like chat relation tabs', () {
    final discoverText = File(
      'lib/modules/home/discover_page.dart',
    ).readAsStringSync();
    final rankingProviderText = File(
      'lib/app/providers/ranking_provider.dart',
    ).readAsStringSync();

    expect(discoverText, contains('TabController _momentCategoryController'));
    expect(discoverText, contains('TabController _rankingCategoryController'));
    expect(discoverText, contains('_DiscoverCategorySegment'));
    expect(discoverText, contains('controller.animateTo(index)'));
    expect(discoverText, contains('final handler = onSelected'));
    expect(discoverText, contains('children: MomentFeedCategory.values.map'));
    expect(discoverText, contains('RankingBoard.values.expand'));
    expect(discoverText, contains('RankingPeriod.values.map'));
    expect(discoverText, contains('_rankingPageIndex'));
    expect(discoverText, contains('_onMomentPageChanged'));
    expect(discoverText, contains('_onRankingPageChanged'));
    expect(discoverText, contains('setSelection('));
    expect(rankingProviderText, contains('void setSelection'));
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
