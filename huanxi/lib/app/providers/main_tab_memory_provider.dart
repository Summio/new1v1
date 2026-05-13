import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'moment_provider.dart';

class MainTabMemoryState {
  final int homeCategoryIndex;
  final int discoverTabIndex;
  final MomentFeedCategory discoverMomentCategory;
  final int chatTabIndex;
  final int relationTabIndex;

  const MainTabMemoryState({
    this.homeCategoryIndex = 0,
    this.discoverTabIndex = 0,
    this.discoverMomentCategory = MomentFeedCategory.latest,
    this.chatTabIndex = 0,
    this.relationTabIndex = 0,
  });

  MainTabMemoryState copyWith({
    int? homeCategoryIndex,
    int? discoverTabIndex,
    MomentFeedCategory? discoverMomentCategory,
    int? chatTabIndex,
    int? relationTabIndex,
  }) {
    return MainTabMemoryState(
      homeCategoryIndex: homeCategoryIndex ?? this.homeCategoryIndex,
      discoverTabIndex: discoverTabIndex ?? this.discoverTabIndex,
      discoverMomentCategory:
          discoverMomentCategory ?? this.discoverMomentCategory,
      chatTabIndex: chatTabIndex ?? this.chatTabIndex,
      relationTabIndex: relationTabIndex ?? this.relationTabIndex,
    );
  }
}

class MainTabMemoryNotifier extends StateNotifier<MainTabMemoryState> {
  MainTabMemoryNotifier() : super(const MainTabMemoryState());

  void setHomeCategoryIndex(int index) {
    if (index < 0 || index > 2 || state.homeCategoryIndex == index) return;
    state = state.copyWith(homeCategoryIndex: index);
  }

  void setDiscoverTabIndex(int index) {
    if (index < 0 || index > 1 || state.discoverTabIndex == index) return;
    state = state.copyWith(discoverTabIndex: index);
  }

  void setDiscoverMomentCategory(MomentFeedCategory category) {
    if (state.discoverMomentCategory == category) return;
    state = state.copyWith(discoverMomentCategory: category);
  }

  void setChatTabIndex(int index) {
    if (index < 0 || index > 2 || state.chatTabIndex == index) return;
    state = state.copyWith(chatTabIndex: index);
  }

  void setRelationTabIndex(int index) {
    if (index < 0 || index > 2 || state.relationTabIndex == index) return;
    state = state.copyWith(relationTabIndex: index);
  }
}

final mainTabMemoryProvider =
    StateNotifierProvider<MainTabMemoryNotifier, MainTabMemoryState>((ref) {
      return MainTabMemoryNotifier();
    });
