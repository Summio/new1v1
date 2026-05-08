import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/moment_provider.dart';
import '../../app/providers/ranking_provider.dart';
import '../../app/routes/app_router.dart';
import 'moment_list_view.dart';

/// 发现页 - 动态 / 排行榜
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
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

class _FeedTabState extends ConsumerState<_FeedTab> {
  MomentFeedCategory _category = MomentFeedCategory.latest;

  @override
  void initState() {
    super.initState();
    // 首次加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLoaded(_category);
    });
  }

  void _ensureLoaded(MomentFeedCategory category) {
    final state = ref.read(momentFeedProvider(category));
    if (state.moments.isEmpty && !state.isLoading) {
      ref.read(momentFeedProvider(category).notifier).load();
    }
  }

  void _selectCategory(MomentFeedCategory category) {
    if (_category == category) return;
    setState(() {
      _category = category;
    });
    _ensureLoaded(category);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(momentFeedProvider(_category));

    return Column(
      children: [
        const SizedBox(height: 12),
        _MomentFeedSegment(selected: _category, onSelected: _selectCategory),
        const SizedBox(height: 4),
        Expanded(
          child: MomentListView(
            moments: state.moments,
            isLoading: state.isLoading,
            isLoadingMore: state.isLoadingMore,
            hasMore: state.hasMore,
            error: state.error,
            emptyTitle: _category.emptyTitle,
            emptySubtitle: _category == MomentFeedCategory.following
                ? '关注用户后可在这里查看动态'
                : '稍后再来看看吧',
            onRefresh: () =>
                ref.read(momentFeedProvider(_category).notifier).load(),
            onLoadMore: () =>
                ref.read(momentFeedProvider(_category).notifier).loadMore(),
          ),
        ),
      ],
    );
  }
}

class _MomentFeedSegment extends StatelessWidget {
  final MomentFeedCategory selected;
  final ValueChanged<MomentFeedCategory> onSelected;

  const _MomentFeedSegment({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: MomentFeedCategory.values.map((item) {
          final active = item == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 排行榜 Tab
class _RankingTab extends ConsumerStatefulWidget {
  const _RankingTab();

  @override
  ConsumerState<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends ConsumerState<_RankingTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(rankingProvider);
      if (state.rows.isEmpty && !state.isLoading) {
        ref.read(rankingProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rankingProvider);

    return Column(
      children: [
        const SizedBox(height: 14),
        _RankingSegment<RankingBoard>(
          values: RankingBoard.values,
          selected: state.board,
          labelBuilder: (item) => item.label,
          onSelected: (item) =>
              ref.read(rankingProvider.notifier).setBoard(item),
        ),
        const SizedBox(height: 10),
        _RankingSegment<RankingPeriod>(
          values: RankingPeriod.values,
          selected: state.period,
          labelBuilder: (item) => item.label,
          onSelected: (item) =>
              ref.read(rankingProvider.notifier).setPeriod(item),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(rankingProvider.notifier).refresh(),
            child: _RankingContent(
              state: state,
              onRetry: () => ref.read(rankingProvider.notifier).load(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RankingSegment<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T item) labelBuilder;
  final ValueChanged<T> onSelected;

  const _RankingSegment({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: values.map((item) {
          final active = item == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  labelBuilder(item),
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
        onTap: () {
          final uri = Uri(
            path: AppRoutes.certifiedUserDetail,
            queryParameters: {'userId': item.userId.toString()},
          );
          context.push(uri.toString());
        },
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
                          : '用户${item.userId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID：${item.userId}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
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
