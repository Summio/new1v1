import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/main_tab_memory_provider.dart';
import 'package:huanxi/app/providers/moment_provider.dart';

void main() {
  test('main tab memory defaults to first page selections', () {
    const state = MainTabMemoryState();

    expect(state.homeCategoryIndex, 0);
    expect(state.discoverTabIndex, 0);
    expect(state.discoverMomentCategory, MomentFeedCategory.latest);
    expect(state.chatTabIndex, 0);
    expect(state.relationTabIndex, 0);
  });

  test('main tab memory updates each remembered page selection', () {
    final notifier = MainTabMemoryNotifier();

    notifier.setHomeCategoryIndex(1);
    notifier.setDiscoverTabIndex(1);
    notifier.setDiscoverMomentCategory(MomentFeedCategory.following);
    notifier.setChatTabIndex(2);
    notifier.setRelationTabIndex(2);

    expect(notifier.state.homeCategoryIndex, 1);
    expect(notifier.state.discoverTabIndex, 1);
    expect(notifier.state.discoverMomentCategory, MomentFeedCategory.following);
    expect(notifier.state.chatTabIndex, 2);
    expect(notifier.state.relationTabIndex, 2);
  });

  test('main tab memory ignores invalid tab indexes', () {
    final notifier = MainTabMemoryNotifier();

    notifier.setHomeCategoryIndex(1);
    notifier.setDiscoverTabIndex(1);
    notifier.setChatTabIndex(2);
    notifier.setRelationTabIndex(2);

    notifier.setHomeCategoryIndex(-1);
    notifier.setHomeCategoryIndex(3);
    notifier.setDiscoverTabIndex(-1);
    notifier.setDiscoverTabIndex(2);
    notifier.setChatTabIndex(-1);
    notifier.setChatTabIndex(3);
    notifier.setRelationTabIndex(-1);
    notifier.setRelationTabIndex(3);

    expect(notifier.state.homeCategoryIndex, 1);
    expect(notifier.state.discoverTabIndex, 1);
    expect(notifier.state.chatTabIndex, 2);
    expect(notifier.state.relationTabIndex, 2);
  });
}
