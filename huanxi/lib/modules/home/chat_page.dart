import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/main_tab_memory_provider.dart';
import '../../app/theme/app_theme.dart';
import 'call_page.dart';
import 'messages_page.dart';
import 'my_following_page.dart';

class ChatPage extends ConsumerStatefulWidget {
  final int? initialTabIndexOverride;
  final int? initialRelationTabIndexOverride;

  const ChatPage({
    super.key,
    this.initialTabIndexOverride,
    this.initialRelationTabIndexOverride,
  });

  static int tabIndexFromQuery(String? value) {
    switch (value) {
      case 'call':
        return 1;
      case 'relations':
        return 2;
      case 'messages':
      default:
        return 0;
    }
  }

  static int relationTabIndexFromQuery(String? value) {
    switch (value) {
      case 'fans':
        return 1;
      case 'blacklist':
        return 2;
      case 'following':
      default:
        return 0;
    }
  }

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with SingleTickerProviderStateMixin {
  static const int _messagePageIndex = 0;
  static const int _callPageIndex = 1;
  static const int _relationFirstPageIndex = 2;
  static const int _chatPageCount = 5;

  late final TabController _tabController;
  late int _currentPageIndex;

  @override
  void initState() {
    super.initState();
    final memory = ref.read(mainTabMemoryProvider);
    _currentPageIndex = _pageForMainTabIndex(
      widget.initialTabIndexOverride ?? memory.chatTabIndex,
      relationTabIndex:
          widget.initialRelationTabIndexOverride ?? memory.relationTabIndex,
    );
    _tabController = TabController(
      length: _chatPageCount,
      initialIndex: _currentPageIndex,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    _writeRememberedIndexes(_currentPageIndex);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  int _pageForMainTabIndex(int index, {int? relationTabIndex}) {
    switch (index) {
      case 1:
        return _callPageIndex;
      case 2:
        return _pageForRelationTabIndex(relationTabIndex ?? 0);
      case 0:
      default:
        return _messagePageIndex;
    }
  }

  int _pageForRelationTabIndex(int index) {
    return _relationFirstPageIndex + index.clamp(0, 2);
  }

  int _mainTabIndexForPage(int pageIndex) {
    if (pageIndex == _callPageIndex) return 1;
    if (pageIndex >= _relationFirstPageIndex) return 2;
    return 0;
  }

  int _relationTabIndexForPage(int pageIndex) {
    return (pageIndex - _relationFirstPageIndex).clamp(0, 2);
  }

  bool _isRelationPage(int pageIndex) {
    return pageIndex >= _relationFirstPageIndex;
  }

  void _onTabChanged() {
    final nextIndex = _tabController.index;
    if (_currentPageIndex != nextIndex) {
      setState(() {
        _currentPageIndex = nextIndex;
      });
    }
    _writeRememberedIndexes(nextIndex);
  }

  void _writeRememberedIndexes(int pageIndex) {
    final notifier = ref.read(mainTabMemoryProvider.notifier);
    notifier.setChatTabIndex(_mainTabIndexForPage(pageIndex));
    if (_isRelationPage(pageIndex)) {
      notifier.setRelationTabIndex(_relationTabIndexForPage(pageIndex));
    }
  }

  void _selectMainTab(int index) {
    if (index == 2 && _isRelationPage(_currentPageIndex)) return;
    final rememberedRelationIndex = ref
        .read(mainTabMemoryProvider)
        .relationTabIndex;
    _tabController.animateTo(
      _pageForMainTabIndex(index, relationTabIndex: rememberedRelationIndex),
    );
  }

  void _selectRelationTab(int index) {
    _tabController.animateTo(_pageForRelationTabIndex(index));
  }

  @override
  Widget build(BuildContext context) {
    final mainTabIndex = _mainTabIndexForPage(_currentPageIndex);
    final relationTabIndex = _relationTabIndexForPage(_currentPageIndex);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '聊天',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
      ),
      body: Column(
        children: [
          _ChatCategorySegment(
            labels: const ['消息', '通话', '关系'],
            controller: _tabController,
            selectedIndex: mainTabIndex,
            onSelected: _selectMainTab,
          ),
          const SizedBox(height: 8),
          if (_isRelationPage(_currentPageIndex)) ...[
            _ChatCategorySegment(
              labels: const ['关注', '粉丝', '黑名单'],
              controller: _tabController,
              selectedIndex: relationTabIndex,
              onSelected: _selectRelationTab,
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                MessagesPage.embedded(),
                CallPage.embedded(),
                MyFollowingPage.embedded(),
                MyFansPage.embedded(),
                MyBlacklistPage.embedded(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatCategorySegment extends StatelessWidget {
  final List<String> labels;
  final TabController controller;
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  const _ChatCategorySegment({
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
