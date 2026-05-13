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
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final rememberedIndex = ref.read(mainTabMemoryProvider).chatTabIndex;
    final initialIndex = widget.initialTabIndexOverride ?? rememberedIndex;
    _tabController = TabController(
      length: 3,
      initialIndex: initialIndex.clamp(0, 2),
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    ref
        .read(mainTabMemoryProvider.notifier)
        .setChatTabIndex(_tabController.index);
  }

  void _onTabChanged() {
    ref
        .read(mainTabMemoryProvider.notifier)
        .setChatTabIndex(_tabController.index);
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
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const MessagesPage.embedded(),
                const CallPage.embedded(),
                _RelationTabs(
                  initialIndexOverride: widget.initialRelationTabIndexOverride,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationTabs extends ConsumerStatefulWidget {
  final int? initialIndexOverride;

  const _RelationTabs({required this.initialIndexOverride});

  @override
  ConsumerState<_RelationTabs> createState() => _RelationTabsState();
}

class _RelationTabsState extends ConsumerState<_RelationTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _relationTabController;

  @override
  void initState() {
    super.initState();
    final rememberedIndex = ref.read(mainTabMemoryProvider).relationTabIndex;
    final initialIndex = widget.initialIndexOverride ?? rememberedIndex;
    _relationTabController = TabController(
      length: 3,
      initialIndex: initialIndex.clamp(0, 2),
      vsync: this,
    );
    _relationTabController.addListener(_onRelationTabChanged);
    ref
        .read(mainTabMemoryProvider.notifier)
        .setRelationTabIndex(_relationTabController.index);
  }

  void _onRelationTabChanged() {
    ref
        .read(mainTabMemoryProvider.notifier)
        .setRelationTabIndex(_relationTabController.index);
  }

  @override
  void dispose() {
    _relationTabController.removeListener(_onRelationTabChanged);
    _relationTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _ChatCategorySegment(
          labels: const ['关注', '粉丝', '黑名单'],
          controller: _relationTabController,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _relationTabController,
            children: const [
              MyFollowingPage.embedded(),
              MyFansPage.embedded(),
              MyBlacklistPage.embedded(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatCategorySegment extends StatelessWidget {
  final List<String> labels;
  final TabController controller;

  const _ChatCategorySegment({required this.labels, required this.controller});

  @override
  Widget build(BuildContext context) {
    final animation = controller.animation;
    return AnimatedBuilder(
      animation: animation ?? controller,
      builder: (context, _) {
        final selectedIndex = controller.index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: List.generate(labels.length, (index) {
              final active = selectedIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => controller.animateTo(index),
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
