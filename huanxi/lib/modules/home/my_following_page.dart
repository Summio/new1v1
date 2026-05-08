import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/user_follow_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_toast.dart';
import '../../services/user_home_service.dart';

class MyFollowingPage extends ConsumerStatefulWidget {
  final bool fansMode;

  const MyFollowingPage({super.key}) : fansMode = false;

  const MyFollowingPage.fans({super.key}) : fansMode = true;

  @override
  ConsumerState<MyFollowingPage> createState() => _MyFollowingPageState();
}

class MyFansPage extends MyFollowingPage {
  const MyFansPage({super.key}) : super.fans();
}

class _MyFollowingPageState extends ConsumerState<MyFollowingPage> {
  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int? _processingUserId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(_provider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(_provider.notifier).loadMore();
    }
  }

  AutoDisposeStateNotifierProvider<MyFollowingNotifier, MyFollowingState>
  get _provider => widget.fansMode ? myFansProvider : myFollowingProvider;

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

  Future<void> _cancelFollowing(FollowingUserItem item) async {
    if (_processingUserId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认取消关注'),
        content: Text('确定不再关注 ${_displayName(item)} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('不再关注'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _processingUserId = item.user.userId;
    });

    try {
      await UserHomeService.instance.unfollowUser(item.user.userId);
      if (!mounted) return;
      ref.read(_provider.notifier).removeFollowing(item.user.userId);
      AppToast.showSnackBar(context, const SnackBar(content: Text('已取消关注')));
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('取消关注失败，请稍后重试')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingUserId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final title = widget.fansMode ? '我的粉丝' : '我的关注';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          state.totalCount > 0 ? '$title (${state.totalCount})' : title,
        ),
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
                  hintText: widget.fansMode ? '搜索粉丝昵称或用户ID' : '搜索已关注的昵称或用户ID',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      state.keyword.isNotEmpty
                          ? '筛选结果：${state.totalCount} 人'
                          : '共 ${state.totalCount} 人',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (state.keyword.isNotEmpty)
                    Flexible(
                      child: Text(
                        '关键词：${state.keyword}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
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
        message: widget.fansMode ? '加载粉丝列表中...' : '加载关注列表中...',
      );
    }
    if (state.error != null && state.users.isEmpty) {
      return StatusView.error(message: state.error!, onRetry: _refresh);
    }
    if (state.users.isEmpty) {
      return StatusView.empty(
        message: state.keyword.isNotEmpty
            ? (widget.fansMode ? '没有找到匹配的粉丝' : '没有找到匹配的关注')
            : (widget.fansMode ? '你还没有粉丝' : '你还没有关注任何人'),
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
            isProcessing: _processingUserId == item.user.userId,
            onTap: () => context.push(AppRoutes.anchorDetail, extra: item.user),
            onCancel: widget.fansMode ? null : () => _cancelFollowing(item),
          );
        },
      ),
    );
  }

  String _displayName(FollowingUserItem item) {
    final user = item.user;
    return user.username?.trim().isNotEmpty == true
        ? user.username!.trim()
        : '用户${user.userId}';
  }
}

class _FollowingTile extends StatelessWidget {
  final FollowingUserItem item;
  final bool isProcessing;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  const _FollowingTile({
    required this.item,
    required this.isProcessing,
    required this.onTap,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final user = item.user;
    final name = user.username?.trim().isNotEmpty == true
        ? user.username!.trim()
        : '用户${user.userId}';
    final isOnline = user.isOnline ?? false;

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
                        Expanded(
                          child: GestureDetector(
                            onTap: onTap,
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
                        ),
                        _UserTypeBadge(isAnchor: user.isAnchor),
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
                            color: isOnline
                                ? AppTheme.onlineGreen
                                : AppTheme.offlineGray,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? '在线' : '离线',
                          style: TextStyle(
                            color: isOnline
                                ? AppTheme.onlineGreen
                                : AppTheme.textHint,
                            fontSize: 12,
                          ),
                        ),
                        if (item.followedAt != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '关注于 ${_formatFollowedAt(item.followedAt!)}',
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
              if (onCancel != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: const BorderSide(color: AppTheme.errorColor),
                    foregroundColor: AppTheme.errorColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: Icon(
                    isProcessing
                        ? Icons.hourglass_top_rounded
                        : Icons.favorite_border_rounded,
                    size: 16,
                  ),
                  label: Text(isProcessing ? '处理中' : '取消关注'),
                ),
              ],
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

class _UserTypeBadge extends StatelessWidget {
  final bool isAnchor;

  const _UserTypeBadge({required this.isAnchor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAnchor
            ? AppTheme.primaryColor.withValues(alpha: 0.12)
            : AppTheme.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAnchor ? '主播' : '用户',
        style: TextStyle(
          color: isAnchor ? AppTheme.primaryColor : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
