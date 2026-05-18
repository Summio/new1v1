import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/user_follow_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../app/widgets/vip_badge.dart';
import '../../services/user_home_service.dart' show FollowingUserItem;
import 'main_shell.dart';

Color _availabilityColor(String status) {
  switch (status) {
    case 'online':
      return AppTheme.onlineGreen;
    case 'busy':
      return const Color(0xFFFF3B30);
    case 'dnd':
      return const Color(0xFFAF52DE);
    default:
      return AppTheme.offlineGray;
  }
}

class MyFollowingPage extends ConsumerStatefulWidget {
  final bool fansMode;
  final bool blacklistMode;
  final bool embedded;

  const MyFollowingPage({super.key})
    : fansMode = false,
      blacklistMode = false,
      embedded = false;

  const MyFollowingPage.embedded({super.key})
    : fansMode = false,
      blacklistMode = false,
      embedded = true;

  const MyFollowingPage.fans({super.key, this.embedded = false})
    : fansMode = true,
      blacklistMode = false;

  const MyFollowingPage.blacklist({super.key, this.embedded = false})
    : fansMode = false,
      blacklistMode = true;

  @override
  ConsumerState<MyFollowingPage> createState() => _MyFollowingPageState();
}

class MyFansPage extends MyFollowingPage {
  const MyFansPage({super.key}) : super.fans();

  const MyFansPage.embedded({super.key}) : super.fans(embedded: true);
}

class MyBlacklistPage extends MyFollowingPage {
  const MyBlacklistPage({super.key}) : super.blacklist();

  const MyBlacklistPage.embedded({super.key}) : super.blacklist(embedded: true);
}

class _MyFollowingPageState extends ConsumerState<MyFollowingPage> {
  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<PresenceEvent>? _presenceSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _presenceSubscription = MainShell.presenceStream.listen(
      _handlePresenceEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(_provider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _handlePresenceEvent(PresenceEvent event) {
    ref
        .read(_provider.notifier)
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
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(_provider.notifier).loadMore();
    }
  }

  AutoDisposeStateNotifierProvider<MyFollowingNotifier, MyFollowingState>
  get _provider => widget.blacklistMode
      ? myBlacklistProvider
      : (widget.fansMode ? myFansProvider : myFollowingProvider);

  Future<void> _refresh() async {
    await ref.read(_provider.notifier).refresh();
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    ref.read(_provider.notifier).search(_keywordController.text);
  }

  Future<void> _clearSearch() async {
    if (_keywordController.text.isEmpty) return;
    _keywordController.clear();
    setState(() {});
    await ref.read(_provider.notifier).search('');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final title = widget.blacklistMode
        ? (widget.embedded ? '黑名单' : '我的黑名单')
        : (widget.embedded
              ? (widget.fansMode ? '粉丝' : '关注')
              : (widget.fansMode ? '我的粉丝' : '我的关注'));

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: widget.embedded
          ? null
          : AppBar(
              centerTitle: true,
              title: Text(title),
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refresh,
                ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _keywordController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.blacklistMode
                      ? '搜索拉黑的昵称或用户ID'
                      : (widget.fansMode ? '搜索粉丝的昵称或用户ID' : '搜索关注的昵称或用户ID'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _keywordController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            if (state.error != null && state.users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.error!,
                    style: const TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(MyFollowingState state) {
    if (state.isLoading && state.users.isEmpty) {
      return StatusView.loading(
        message: widget.blacklistMode
            ? '加载黑名单中...'
            : (widget.fansMode ? '加载粉丝列表中...' : '加载关注列表中...'),
      );
    }
    if (state.error != null && state.users.isEmpty) {
      return StatusView.error(message: state.error!, onRetry: _refresh);
    }
    if (state.users.isEmpty) {
      return StatusView.empty(
        message: state.keyword.isNotEmpty
            ? (widget.blacklistMode
                  ? '没有找到匹配的黑名单用户'
                  : (widget.fansMode ? '没有找到匹配的粉丝' : '没有找到匹配的关注'))
            : (widget.blacklistMode
                  ? '你还没有拉黑任何人'
                  : (widget.fansMode ? '你还没有粉丝' : '你还没有关注任何人')),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: state.users.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= state.users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = state.users[index];
          return _FollowingTile(
            item: item,
            onTap: () =>
                context.push(AppRoutes.certifiedUserDetail, extra: item.user),
            dateLabel: widget.blacklistMode ? '拉黑于' : '关注于',
          );
        },
      ),
    );
  }
}

class _FollowingTile extends StatelessWidget {
  final FollowingUserItem item;
  final VoidCallback onTap;
  final String dateLabel;

  const _FollowingTile({
    required this.item,
    required this.onTap,
    this.dateLabel = '关注于',
  });

  @override
  Widget build(BuildContext context) {
    final user = item.user;
    final name = user.username?.trim().isNotEmpty == true
        ? user.username!.trim()
        : '用户${user.userId}';
    final availabilityStatus = user.availabilityStatus;
    final statusColor = _availabilityColor(availabilityStatus);
    final statusLabel = user.availabilityLabel;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              GestureDetector(
                onTap: onTap,
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.placeholderColor,
                  backgroundImage:
                      user.avatar != null && user.avatar!.trim().isNotEmpty
                      ? NetworkImage(user.avatar!.trim())
                      : null,
                  child: user.avatar == null || user.avatar!.trim().isEmpty
                      ? const Icon(Icons.person, color: AppTheme.textSecondary)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (user.isVip) ...[
                          const SizedBox(width: 4),
                          const VipBadge(dense: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ID：${user.userId}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                        if ((item.blockedAt ?? item.followedAt) != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$dateLabel ${_formatFollowedAt((item.blockedAt ?? item.followedAt)!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textHint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFollowedAt(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
