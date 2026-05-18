import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/main_tab_memory_provider.dart';
import '../../app/providers/moment_provider.dart';
import '../../app/providers/ranking_provider.dart';
import '../../app/routes/app_router.dart';
import 'moment_list_view.dart';

/// 发现页 - 动态 / 排行榜
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = ref.read(mainTabMemoryProvider).discoverTabIndex;
    _tabController = TabController(
      length: 2,
      initialIndex: initialIndex,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    ref
        .read(mainTabMemoryProvider.notifier)
        .setDiscoverTabIndex(_tabController.index);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // Tab 切换
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF8E8E93),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: '动态'),
                Tab(text: '排行榜'),
              ],
            ),
          ),

          // Tab 内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_FeedTab(), _RankingTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态 Tab
class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab();

  @override
  ConsumerState<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<_FeedTab>
    with SingleTickerProviderStateMixin {
  late final TabController _momentCategoryController;

  @override
  void initState() {
    super.initState();
    final rememberedCategory = ref
        .read(mainTabMemoryProvider)
        .discoverMomentCategory;
    _momentCategoryController = TabController(
      length: MomentFeedCategory.values.length,
      initialIndex: MomentFeedCategory.values.indexOf(rememberedCategory),
      vsync: this,
    );
    _momentCategoryController.addListener(_onMomentPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLoaded(MomentFeedCategory.values[_momentCategoryController.index]);
    });
  }

  @override
  void dispose() {
    _momentCategoryController.removeListener(_onMomentPageChanged);
    _momentCategoryController.dispose();
    super.dispose();
  }

  void _ensureLoaded(MomentFeedCategory category) {
    final state = ref.read(momentFeedProvider(category));
    if (state.moments.isEmpty && !state.isLoading) {
      ref.read(momentFeedProvider(category).notifier).load();
    }
  }

  void _onMomentPageChanged() {
    final category = MomentFeedCategory.values[_momentCategoryController.index];
    ref
        .read(mainTabMemoryProvider.notifier)
        .setDiscoverMomentCategory(category);
    _ensureLoaded(category);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        _DiscoverCategorySegment(
          labels: MomentFeedCategory.values
              .map((category) => category.label)
              .toList(),
          controller: _momentCategoryController,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            controller: _momentCategoryController,
            children: MomentFeedCategory.values.map((category) {
              return _MomentCategoryPage(category: category);
            }).toList(),
          ),
        ),
      ],
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

/// 排行榜 Tab
class _RankingTab extends ConsumerStatefulWidget {
  const _RankingTab();

  @override
  ConsumerState<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends ConsumerState<_RankingTab>
    with TickerProviderStateMixin {
  late final TabController _rankingCategoryController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(rankingProvider);
    _rankingCategoryController = TabController(
      length: RankingBoard.values.length * RankingPeriod.values.length,
      initialIndex: _rankingPageIndex(state.board, state.period),
      vsync: this,
    );
    _rankingCategoryController.addListener(_onRankingPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nextState = ref.read(rankingProvider);
      if (nextState.rows.isEmpty && !nextState.isLoading) {
        ref.read(rankingProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _rankingCategoryController.removeListener(_onRankingPageChanged);
    _rankingCategoryController.dispose();
    super.dispose();
  }

  int _rankingPageIndex(RankingBoard board, RankingPeriod period) {
    return RankingBoard.values.indexOf(board) * RankingPeriod.values.length +
        RankingPeriod.values.indexOf(period);
  }

  RankingBoard _rankingBoardForPage(int index) {
    return RankingBoard.values[index ~/ RankingPeriod.values.length];
  }

  RankingPeriod _rankingPeriodForPage(int index) {
    return RankingPeriod.values[index % RankingPeriod.values.length];
  }

  void _onRankingPageChanged() {
    final index = _rankingCategoryController.index;
    ref
        .read(rankingProvider.notifier)
        .setSelection(
          board: _rankingBoardForPage(index),
          period: _rankingPeriodForPage(index),
        );
  }

  void _selectRankingBoard(int index) {
    final state = ref.read(rankingProvider);
    _rankingCategoryController.animateTo(
      _rankingPageIndex(RankingBoard.values[index], state.period),
    );
  }

  void _selectRankingPeriod(int index) {
    final state = ref.read(rankingProvider);
    _rankingCategoryController.animateTo(
      _rankingPageIndex(state.board, RankingPeriod.values[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rankingProvider);

    return Column(
      children: [
        const SizedBox(height: 14),
        _DiscoverCategorySegment(
          labels: RankingBoard.values.map((board) => board.label).toList(),
          controller: _rankingCategoryController,
          selectedIndex: RankingBoard.values.indexOf(state.board),
          onSelected: _selectRankingBoard,
        ),
        const SizedBox(height: 10),
        _DiscoverCategorySegment(
          labels: RankingPeriod.values.map((period) => period.label).toList(),
          controller: _rankingCategoryController,
          selectedIndex: RankingPeriod.values.indexOf(state.period),
          onSelected: _selectRankingPeriod,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TabBarView(
            controller: _rankingCategoryController,
            children: RankingBoard.values.expand((_) {
              return RankingPeriod.values.map((_) {
                return RefreshIndicator(
                  onRefresh: () => ref.read(rankingProvider.notifier).refresh(),
                  child: _RankingContent(
                    state: state,
                    onRetry: () => ref.read(rankingProvider.notifier).load(),
                  ),
                );
              });
            }).toList(),
          ),
        ),
      ],
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
                    Text(
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
