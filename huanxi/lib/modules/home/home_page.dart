import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/anchor_provider.dart';
import '../../app/theme/app_theme.dart';

/// 首页 - 主播列表 + 分类 Tab
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _pageController = PageController();

  final List<String> _categories = ['推荐', '活跃', '新人'];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    Future.microtask(() {
      ref.read(anchorListProvider.notifier).fetchAnchors(refresh: true);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // 只有 Tab 被直接点击（由 TabController 动画触发）时才同步 PageView
    // PageView 滑动触发的 Tab 动画期间 indexIsChanging=true，这里会跳过，避免循环
    if (_tabController.indexIsChanging) {
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
      // PageView 滑动后同步 Tab（此时 indexIsChanging 为 false，不会触发 _onTabChanged 中的动画）
      _tabController.animateTo(index);
    }
  }

  void _onTabTap(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchorState = ref.watch(anchorListProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '欢喜',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: -1.0,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.black, size: 28),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 顶部分类 Tab - 药丸风格 + 左右滑动
          Container(
            height: 64,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: List.generate(_categories.length, (index) {
                final isActive = _currentIndex == index;
                return GestureDetector(
                  onTap: () => _onTabTap(index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.black : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _categories[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                        color: isActive ? Colors.white : const Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // 主播列表 - PageView 支持左右滑动
          Expanded(
            child: anchorState.isLoading && anchorState.anchors.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : anchorState.error != null && anchorState.anchors.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
                            const SizedBox(height: 16),
                            Text(anchorState.error!),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => ref.read(anchorListProvider.notifier).refresh(),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : PageView.builder(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          return _AnchorListPage(pageIndex: index, pageController: _pageController);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 主播列表分页页面（支持触底加载）
class _AnchorListPage extends ConsumerStatefulWidget {
  final int pageIndex;
  final PageController pageController;

  const _AnchorListPage({required this.pageIndex, required this.pageController});

  @override
  ConsumerState<_AnchorListPage> createState() => _AnchorListPageState();
}

class _AnchorListPageState extends ConsumerState<_AnchorListPage> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(anchorListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchorState = ref.watch(anchorListProvider);

    if (anchorState.isLoading && anchorState.anchors.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (anchorState.error != null && anchorState.anchors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(anchorState.error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(anchorListProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(anchorListProvider.notifier).refresh(),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: anchorState.anchors.length,
        itemBuilder: (context, idx) {
          final anchor = anchorState.anchors[idx];
          return _AnchorCard(anchor: anchor);
        },
      ),
    );
  }
}

class _AnchorCard extends StatefulWidget {
  final AnchorInfo anchor;

  const _AnchorCard({required this.anchor});

  @override
  State<_AnchorCard> createState() => _AnchorCardState();
}

class _AnchorCardState extends State<_AnchorCard> {
  bool _isNavigating = false;

  Future<void> _openDetail() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await context.push(AppRoutes.anchorDetail, extra: widget.anchor);
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final isOnline = anchor.isOnline ?? false;

    return GestureDetector(
      onTap: _openDetail,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
          final rawCacheWidth = (constraints.maxWidth * devicePixelRatio).round();
          final rawCacheHeight = (constraints.maxHeight * devicePixelRatio).round();
          final cacheWidth = rawCacheWidth > 720 ? 720 : rawCacheWidth;
          final cacheHeight = rawCacheHeight > 960 ? 960 : rawCacheHeight;
          return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFFF2F2F7),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 照片
            Hero(
              tag: 'anchor_avatar_${anchor.userId}',
              child: anchor.avatar != null && anchor.avatar!.isNotEmpty
                  ? Image.network(
                      anchor.avatar!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      cacheWidth: cacheWidth,
                      cacheHeight: cacheHeight,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(color: const Color(0xFFEFEFF4));
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.person, size: 40, color: Colors.grey),
                        );
                      },
                    )
                  : const Center(child: Icon(Icons.person, size: 40, color: Colors.grey)),
            ),

            // 蒙层
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                    stops: const [0.7, 1.0],
                  ),
                ),
              ),
            ),

            // 在线标识
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOnline ? AppTheme.onlineGreen : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? '在线' : '离线',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底部文字
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    anchor.username ?? '匿名用户',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.diamond_outlined, size: 10, color: Color(0xFFFFD700)),
                      const SizedBox(width: 2),
                      Text(
                        '${anchor.diamonds}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
          );
        },
      ),
    );
  }
}
