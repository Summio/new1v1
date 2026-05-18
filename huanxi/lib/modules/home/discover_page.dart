import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/main_tab_memory_provider.dart';
import '../../app/providers/moment_provider.dart';
import '../../app/providers/ranking_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/vip_badge.dart';
import 'moment_list_view.dart';

/// 发现页 - 动态 / 排行榜
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with SingleTickerProviderStateMixin {
  static final int _momentPageCount = MomentFeedCategory.values.length;
  static final int _rankingFirstPageIndex = MomentFeedCategory.values.length;
  static final int _discoverPageCount =
      _rankingFirstPageIndex +
      RankingBoard.values.length * RankingPeriod.values.length;

  late final TabController _discoverPageController;
  late int _currentPageIndex;

  @override
  void initState() {
    super.initState();
    final memory = ref.read(mainTabMemoryProvider);
    final rankingState = ref.read(rankingProvider);
    _currentPageIndex = memory.discoverTabIndex == 1
        ? _pageForRanking(rankingState.board, rankingState.period)
        : _pageForMomentCategory(memory.discoverMomentCategory);
    _discoverPageController = TabController(
      length: _discoverPageCount,
      initialIndex: _currentPageIndex,
      vsync: this,
    );
    _discoverPageController.addListener(_onDiscoverPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCurrentPage(_discoverPageController.index);
    });
  }

  @override
  void dispose() {
    _discoverPageController.removeListener(_onDiscoverPageChanged);
    _discoverPageController.dispose();
    super.dispose();
  }

  int _pageForDiscoverMainTabIndex(int index) {
    if (index == 1) {
      final rankingState = ref.read(rankingProvider);
      return _pageForRanking(rankingState.board, rankingState.period);
    }
    return _pageForMomentCategory(
      ref.read(mainTabMemoryProvider).discoverMomentCategory,
    );
  }

  int _discoverMainTabIndexForPage(int pageIndex) {
    return pageIndex >= _rankingFirstPageIndex ? 1 : 0;
  }

  int _pageForMomentCategory(MomentFeedCategory category) {
    final index = MomentFeedCategory.values.indexOf(category);
    return index < 0 ? 0 : index;
  }

  MomentFeedCategory _momentCategoryForPage(int pageIndex) {
    return MomentFeedCategory.values[pageIndex.clamp(0, _momentPageCount - 1)];
  }

  int _pageForRanking(RankingBoard board, RankingPeriod period) {
    return _rankingFirstPageIndex +
        RankingBoard.values.indexOf(board) * RankingPeriod.values.length +
        RankingPeriod.values.indexOf(period);
  }

  RankingBoard _rankingBoardForPage(int pageIndex) {
    final rankingIndex = pageIndex - _rankingFirstPageIndex;
    return RankingBoard.values[rankingIndex ~/ RankingPeriod.values.length];
  }

  RankingPeriod _rankingPeriodForPage(int pageIndex) {
    final rankingIndex = pageIndex - _rankingFirstPageIndex;
    return RankingPeriod.values[rankingIndex % RankingPeriod.values.length];
  }

  void _onDiscoverPageChanged() {
    final nextIndex = _discoverPageController.index;
    if (_currentPageIndex != nextIndex) {
      setState(() {
        _currentPageIndex = nextIndex;
      });
    }
    _syncCurrentPage(nextIndex);
  }

  void _syncCurrentPage(int pageIndex) {
    final memoryNotifier = ref.read(mainTabMemoryProvider.notifier);
    memoryNotifier.setDiscoverTabIndex(_discoverMainTabIndexForPage(pageIndex));
    if (pageIndex < _rankingFirstPageIndex) {
      final category = _momentCategoryForPage(pageIndex);
      memoryNotifier.setDiscoverMomentCategory(category);
      _ensureMomentLoaded(category);
      return;
    }
    final notifier = ref.read(rankingProvider.notifier);
    notifier.setSelection(
      board: _rankingBoardForPage(pageIndex),
      period: _rankingPeriodForPage(pageIndex),
    );
    final state = ref.read(rankingProvider);
    if (state.rows.isEmpty && !state.isLoading) {
      notifier.load();
    }
  }

  void _ensureMomentLoaded(MomentFeedCategory category) {
    final state = ref.read(momentFeedProvider(category));
    if (state.moments.isEmpty && !state.isLoading) {
      ref.read(momentFeedProvider(category).notifier).load();
    }
  }

  void _selectDiscoverMainTab(int index) {
    if (_discoverMainTabIndexForPage(_currentPageIndex) == index) return;
    _discoverPageController.animateTo(_pageForDiscoverMainTabIndex(index));
  }

  void _selectMomentCategory(int index) {
    _discoverPageController.animateTo(
      _pageForMomentCategory(MomentFeedCategory.values[index]),
    );
  }

  void _selectRankingBoard(int index) {
    final period = _currentPageIndex >= _rankingFirstPageIndex
        ? _rankingPeriodForPage(_currentPageIndex)
        : ref.read(rankingProvider).period;
    _discoverPageController.animateTo(
      _pageForRanking(RankingBoard.values[index], period),
    );
  }

  void _selectRankingPeriod(int index) {
    final board = _currentPageIndex >= _rankingFirstPageIndex
        ? _rankingBoardForPage(_currentPageIndex)
        : ref.read(rankingProvider).board;
    _discoverPageController.animateTo(
      _pageForRanking(board, RankingPeriod.values[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainTabIndex = _discoverMainTabIndexForPage(_currentPageIndex);
    final showRanking = mainTabIndex == 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '发现',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: -1.0,
          ),
        ),
      ),
      body: Column(
        children: [
          _DiscoverCategorySegment(
            labels: const ['动态', '排行榜'],
            controller: _discoverPageController,
            selectedIndex: mainTabIndex,
            onSelected: _selectDiscoverMainTab,
          ),
          const SizedBox(height: 8),
          if (showRanking) ...[
            _DiscoverCategorySegment(
              labels: RankingBoard.values.map((board) => board.label).toList(),
              controller: _discoverPageController,
              selectedIndex: RankingBoard.values.indexOf(
                _rankingBoardForPage(_currentPageIndex),
              ),
              onSelected: _selectRankingBoard,
            ),
            const SizedBox(height: 10),
            _DiscoverCategorySegment(
              labels: RankingPeriod.values
                  .map((period) => period.label)
                  .toList(),
              controller: _discoverPageController,
              selectedIndex: RankingPeriod.values.indexOf(
                _rankingPeriodForPage(_currentPageIndex),
              ),
              onSelected: _selectRankingPeriod,
            ),
            const SizedBox(height: 10),
          ] else ...[
            _DiscoverCategorySegment(
              labels: MomentFeedCategory.values
                  .map((category) => category.label)
                  .toList(),
              controller: _discoverPageController,
              selectedIndex: _currentPageIndex,
              onSelected: _selectMomentCategory,
            ),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: TabBarView(
              controller: _discoverPageController,
              children: [
                ...MomentFeedCategory.values.map((category) {
                  return _MomentCategoryPage(category: category);
                }),
                ...RankingBoard.values.expand((_) {
                  return RankingPeriod.values.map((_) {
                    return const _RankingPage();
                  });
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentCategoryPage extends ConsumerWidget {
  final MomentFeedCategory category;

  const _MomentCategoryPage({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(momentFeedProvider(category));

    return MomentListView(
      moments: state.moments,
      isLoading: state.isLoading,
      isLoadingMore: state.isLoadingMore,
      hasMore: state.hasMore,
      error: state.error,
      emptyTitle: category.emptyTitle,
      emptySubtitle: category == MomentFeedCategory.following
          ? '关注用户后可在这里查看动态'
          : '稍后再来看看吧',
      onRefresh: () => ref.read(momentFeedProvider(category).notifier).load(),
      onLoadMore: () =>
          ref.read(momentFeedProvider(category).notifier).loadMore(),
    );
  }
}

class _RankingPage extends ConsumerWidget {
  const _RankingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rankingProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(rankingProvider.notifier).refresh(),
      child: _RankingContent(
        state: state,
        onRetry: () => ref.read(rankingProvider.notifier).load(),
      ),
    );
  }
}

class _DiscoverCategorySegment extends StatelessWidget {
  final List<String> labels;
  final TabController controller;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  const _DiscoverCategorySegment({
    required this.labels,
    required this.controller,
    this.selectedIndex,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final animation = controller.animation;
    return AnimatedBuilder(
      animation: animation ?? controller,
      builder: (context, _) {
        final activeIndex = selectedIndex ?? controller.index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: List.generate(labels.length, (index) {
              final active = activeIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    final handler = onSelected;
                    if (handler != null) {
                      handler(index);
                      return;
                    }
                    controller.animateTo(index);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        color: active ? Colors.white : AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _RankingContent extends StatelessWidget {
  final RankingState state;
  final VoidCallback onRetry;

  const _RankingContent({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.error_outline_rounded, size: 54, color: AppTheme.textHint),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                Text(
                  state.error!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ),
        ],
      );
    }
    if (state.rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.leaderboard_outlined, size: 64, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Center(
            child: Text(
              state.board == RankingBoard.invite ? '邀请榜即将上线' : '暂无排行数据',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: state.rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = state.rows[index];
        return _RankingTile(item: item);
      },
    );
  }
}

class _RankingTile extends StatelessWidget {
  final RankingItem item;

  const _RankingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isTopThree = item.rank <= 3;
    final isMissingUserId = item.userId == null;
    final canOpenProfile = !item.isAnonymous && !isMissingUserId;
    final rankColor = switch (item.rank) {
      1 => const Color(0xFFFFB300),
      2 => const Color(0xFF9EA7B3),
      3 => const Color(0xFFD38B5D),
      _ => AppTheme.textSecondary,
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canOpenProfile
            ? () {
                final uri = Uri(
                  path: AppRoutes.certifiedUserDetail,
                  queryParameters: {'userId': item.userId.toString()},
                );
                context.push(uri.toString());
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0F0F0)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Center(
                  child: Text(
                    '${item.rank}',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: isTopThree ? 22 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.placeholderColor,
                backgroundImage: item.avatar.trim().isNotEmpty
                    ? NetworkImage(item.avatar.trim())
                    : null,
                child: item.avatar.trim().isEmpty
                    ? const Icon(Icons.person, color: AppTheme.textSecondary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.nickname.isNotEmpty
                                ? item.nickname
                                : item.isAnonymous
                                ? '神秘人'
                                : '用户${item.userId ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (item.isVip) ...[
                          const SizedBox(width: 4),
                          const VipBadge(dense: true),
                        ],
                      ],
                    ),
                    if (!item.isAnonymous && item.userId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ID：${item.userId}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 128),
                child: Text(
                  item.scoreGapText,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
