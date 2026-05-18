import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/providers/certified_user_provider.dart';
import '../../app/providers/main_tab_memory_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/vip_badge.dart';
import '../../app/widgets/status_view.dart';
import '../../core/utils/app_toast.dart';
import 'flirt_user_list_page.dart';
import 'main_shell.dart';

Color availabilityColor(String status) {
  switch (status) {
    case 'online':
      return AppTheme.onlineGreen;
    case 'busy':
      return const Color(0xFFFF3B30);
    case 'dnd':
      return const Color(0xFFAF52DE);
    default:
      return Colors.grey;
  }
}

String _sectionForIndex(int index) {
  switch (index) {
    case 1:
      return 'active';
    case 2:
      return 'new';
    default:
      return 'recommend';
  }
}

String _formatCallPrice(num? price, String coinName) {
  return '${price?.toStringAsFixed(0) ?? '0'}$coinName/分钟';
}

/// 首页 - 认证用户列表 + 分类 Tab
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final PageController _pageController;

  int _currentIndex = 0;
  int? _programmaticPageTargetIndex;
  bool _showFlirtTab = false;

  List<String> get _categories => ['推荐', '活跃', '新人', if (_showFlirtTab) '搭讪'];

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authProvider);
    _showFlirtTab = authState.isCertifiedUser;
    _currentIndex = _normalizeCategoryIndex(
      ref.read(mainTabMemoryProvider).homeCategoryIndex,
      _categories.length,
    );
    _tabController = TabController(
      length: _categories.length,
      initialIndex: _currentIndex,
      vsync: this,
    );
    _pageController = PageController(initialPage: _currentIndex);
    _tabController.addListener(_onTabChanged);
    Future.microtask(() {
      final notifier = ref.read(certifiedUserListProvider.notifier);
      if (_currentIndex < 3) {
        notifier.setSection(_sectionForIndex(_currentIndex));
        notifier.fetchCertifiedUsers(refresh: true);
      }
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
    if (!_tabController.indexIsChanging) return;
    _selectCategory(_tabController.index, animatePage: true);
  }

  void _commitCategoryIndex(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
    ref.read(mainTabMemoryProvider.notifier).setHomeCategoryIndex(index);
    if (index < 3) {
      ref
          .read(certifiedUserListProvider.notifier)
          .setSection(_sectionForIndex(index));
    }
  }

  void _selectCategory(int index, {required bool animatePage}) {
    _commitCategoryIndex(index);

    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }

    if (animatePage && _pageController.hasClients) {
      _programmaticPageTargetIndex = index;
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    final targetIndex = _programmaticPageTargetIndex;
    if (targetIndex != null && index != targetIndex) {
      return;
    }
    if (targetIndex == index) {
      _programmaticPageTargetIndex = null;
    }
    _commitCategoryIndex(index);
  }

  void _onTabTap(int index) {
    if (_currentIndex == index) return;
    _selectCategory(index, animatePage: true);
  }

  int _normalizeCategoryIndex(int index, int categoryCount) {
    if (index < 0) return 0;
    if (index >= categoryCount) return 0;
    return index;
  }

  void _syncFlirtTabVisibility(bool nextShowFlirtTab) {
    if (_showFlirtTab == nextShowFlirtTab) return;
    final previousIndex = _currentIndex;
    setState(() {
      _showFlirtTab = nextShowFlirtTab;
      _currentIndex = _normalizeCategoryIndex(
        previousIndex,
        _categories.length,
      );
      _programmaticPageTargetIndex = null;
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(
        length: _categories.length,
        initialIndex: _currentIndex,
        vsync: this,
      );
      _tabController.addListener(_onTabChanged);
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
    ref
        .read(mainTabMemoryProvider.notifier)
        .setHomeCategoryIndex(_currentIndex);
    if (_currentIndex < 3) {
      ref
          .read(certifiedUserListProvider.notifier)
          .setSection(_sectionForIndex(_currentIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (_showFlirtTab != authState.isCertifiedUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncFlirtTabVisibility(authState.isCertifiedUser);
      });
    }

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
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.black,
              size: 28,
            ),
            onPressed: () => context.push(AppRoutes.userSearch),
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
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isActive
                            ? Colors.white
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // 认证用户列表 - PageView 支持左右滑动
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                if (_showFlirtTab && index == 3) {
                  return const FlirtUserListPage();
                }
                return _CertifiedUserListPage(
                  pageIndex: index,
                  pageController: _pageController,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 认证用户列表分页页面（支持触底加载）
class _CertifiedUserListPage extends ConsumerStatefulWidget {
  final int pageIndex;
  final PageController pageController;

  const _CertifiedUserListPage({
    required this.pageIndex,
    required this.pageController,
  });

  @override
  ConsumerState<_CertifiedUserListPage> createState() =>
      _CertifiedUserListPageState();
}

class _CertifiedUserListPageState
    extends ConsumerState<_CertifiedUserListPage> {
  static const Duration _contentFadeDuration = Duration(milliseconds: 180);

  late ScrollController _scrollController;
  StreamSubscription<PresenceEvent>? _presenceSubscription;
  bool _isPinning = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _presenceSubscription = MainShell.presenceStream.listen(
      _handlePresenceEvent,
    );
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePresenceEvent(PresenceEvent event) {
    ref
        .read(certifiedUserListProvider.notifier)
        .applyAvailabilityUpdate(
          userId: event.userId,
          online: event.online,
          isBusy: event.isBusy,
          videoDndEnabled: event.videoDndEnabled,
          availabilityStatus: event.availabilityStatus,
          availabilityLabel: event.availabilityLabel,
        );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(certifiedUserListProvider.notifier).loadMore();
    }
  }

  Future<void> _pinActiveCertifiedUser() async {
    if (_isPinning) return;
    setState(() => _isPinning = true);
    try {
      final message = await ref
          .read(certifiedUserListProvider.notifier)
          .pinActiveCertifiedUser();
      if (!mounted) return;
      if (message == null) {
        AppToast.show(context, '已置顶', backgroundColor: AppTheme.onlineGreen);
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
          );
        }
      } else {
        AppToast.show(context, message);
      }
    } finally {
      if (mounted) {
        setState(() => _isPinning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final certifiedUserState = ref.watch(certifiedUserListProvider);
    final coinName = ref.watch(tokenNamesProvider).coinName;
    final authState = ref.watch(authProvider);
    final expectedSection = _sectionForIndex(widget.pageIndex);
    final isCurrentSection = certifiedUserState.section == expectedSection;
    final showActivePin =
        expectedSection == 'active' &&
        isCurrentSection &&
        authState.isCertifiedUser;

    Widget content;
    if (!isCurrentSection) {
      content = StatusView.loading();
    } else if (certifiedUserState.isLoading &&
        certifiedUserState.certifiedUsers.isEmpty) {
      content = StatusView.loading();
    } else if (certifiedUserState.error != null &&
        certifiedUserState.certifiedUsers.isEmpty) {
      content = StatusView.error(
        message: certifiedUserState.error!,
        onRetry: () => ref.read(certifiedUserListProvider.notifier).refresh(),
      );
    } else {
      // RefreshIndicator 包裹 GridView，每个 PageView 页面独立支持下拉刷新
      content = Column(
        children: [
          if (showActivePin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton.icon(
                  onPressed: _isPinning ? null : _pinActiveCertifiedUser,
                  icon: _isPinning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.vertical_align_top_rounded, size: 18),
                  label: const Text('置顶'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(certifiedUserListProvider.notifier).refresh(),
              child: GridView.builder(
                controller: _scrollController,
                physics:
                    const AlwaysScrollableScrollPhysics(), // 确保可以 overscroll 触发下拉刷新
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: certifiedUserState.certifiedUsers.length,
                itemBuilder: (context, idx) {
                  final certifiedUser = certifiedUserState.certifiedUsers[idx];
                  return _CertifiedUserCard(
                    key: ValueKey(
                      'certified_user_card_${certifiedUser.userId}_${certifiedUser.coverUrl ?? ''}',
                    ),
                    certifiedUser: certifiedUser,
                    coinName: coinName,
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return AnimatedSwitcher(
      duration: _contentFadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: KeyedSubtree(
        key: ValueKey(
          '${widget.pageIndex}_${certifiedUserState.section}_${certifiedUserState.isLoading}_${certifiedUserState.certifiedUsers.length}',
        ),
        child: content,
      ),
    );
  }
}

class _CertifiedUserCard extends StatefulWidget {
  final CertifiedUserInfo certifiedUser;
  final String coinName;

  const _CertifiedUserCard({
    super.key,
    required this.certifiedUser,
    required this.coinName,
  });

  @override
  State<_CertifiedUserCard> createState() => _CertifiedUserCardState();
}

class _CertifiedUserCardState extends State<_CertifiedUserCard> {
  static final Uint8List _transparentImage = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
  static const Duration _coverFadeDuration = Duration(milliseconds: 180);

  bool _isNavigating = false;

  Future<void> _openDetail() async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await context.push(
        AppRoutes.certifiedUserDetail,
        extra: widget.certifiedUser,
      );
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final certifiedUser = widget.certifiedUser;
    final availabilityStatus = certifiedUser.availabilityStatus;
    final statusColor = availabilityColor(availabilityStatus);
    final statusLabel = certifiedUser.availabilityLabel;
    final coverUrl = certifiedUser.coverUrl?.trim() ?? '';

    return GestureDetector(
      onTap: _openDetail,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
          final rawCacheWidth = (constraints.maxWidth * devicePixelRatio)
              .round();
          final rawCacheHeight = (constraints.maxHeight * devicePixelRatio)
              .round();
          final cacheWidth = rawCacheWidth > 720 ? 720 : rawCacheWidth;
          final cacheHeight = rawCacheHeight > 960 ? 960 : rawCacheHeight;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: AppTheme.cardBackground,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 照片
                Hero(
                  tag: 'certified_user_avatar_${certifiedUser.userId}',
                  child: coverUrl.isNotEmpty
                      ? FadeInImage.memoryNetwork(
                          key: ValueKey(
                            'certified_user_cover_${certifiedUser.userId}_$coverUrl',
                          ),
                          placeholder: _transparentImage,
                          image: coverUrl,
                          fit: BoxFit.cover,
                          fadeInDuration: _coverFadeDuration,
                          fadeOutDuration: const Duration(milliseconds: 1),
                          filterQuality: FilterQuality.low,
                          imageCacheWidth: cacheWidth,
                          imageCacheHeight: cacheHeight,
                          imageErrorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.grey,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                ),

                // 蒙层
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, AppTheme.overlayMedium],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.badgeBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              certifiedUser.username ?? '匿名用户',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (certifiedUser.isVip) ...[
                            const SizedBox(width: 5),
                            const VipBadge(dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.diamond_outlined,
                            size: 10,
                            color: AppTheme.diamondGold,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatCallPrice(
                              certifiedUser.callPrice,
                              widget.coinName,
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondaryFaint,
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
