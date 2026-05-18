import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/providers/certified_common_phrase_provider.dart';
import '../../app/providers/flirt_user_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/vip_badge.dart';
import '../../app/widgets/status_view.dart';
import '../../core/utils/app_toast.dart';
import 'home_page.dart';
import 'main_shell.dart';

class FlirtUserListPage extends ConsumerStatefulWidget {
  const FlirtUserListPage({super.key});

  @override
  ConsumerState<FlirtUserListPage> createState() => _FlirtUserListPageState();
}

class _FlirtUserListPageState extends ConsumerState<FlirtUserListPage> {
  late final ScrollController _scrollController;
  StreamSubscription<PresenceEvent>? _presenceSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _presenceSubscription = MainShell.presenceStream.listen(
      _handlePresenceEvent,
    );
    Future.microtask(() {
      if (!mounted) return;
      ref.read(flirtUserListProvider.notifier).fetchFlirtUsers(refresh: true);
      ref.read(flirtGreetProvider.notifier).fetchQuota();
    });
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
        .read(flirtUserListProvider.notifier)
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
      ref.read(flirtUserListProvider.notifier).loadMore();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(flirtUserListProvider.notifier).refresh(),
      ref.read(flirtGreetProvider.notifier).fetchQuota(),
    ]);
  }

  Future<void> _sendGreeting() async {
    final greetState = ref.read(flirtGreetProvider);
    final quota = greetState.quota;
    if (!quota.enabled) {
      AppToast.show(context, '打招呼功能已关闭');
      return;
    }
    if (quota.cooldownSeconds > 0) {
      AppToast.show(context, '操作太频繁，请稍后再试');
      return;
    }
    if (quota.remaining <= 0) {
      AppToast.show(context, '今日打招呼次数已用完');
      return;
    }

    await ref.read(certifiedCommonPhrasesProvider.notifier).fetch();
    if (!mounted) return;
    final phrases = ref
        .read(certifiedCommonPhrasesProvider)
        .phrases
        .where((item) => item.approvedContent.trim().isNotEmpty)
        .toList(growable: false);
    if (phrases.isEmpty) {
      AppToast.show(context, '请先设置并通过审核常用语');
      return;
    }

    final selected = await showModalBottomSheet<CertifiedCommonPhraseInfo>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择打招呼常用语',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...phrases.map(
                  (phrase) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppTheme.dividerColor),
                      ),
                      title: Text(
                        phrase.approvedContent,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(phrase),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;

    try {
      final result = await ref
          .read(flirtGreetProvider.notifier)
          .send(slotIndex: selected.slotIndex);
      if (!mounted) return;
      if (!result.started && result.targetCount == 0) {
        AppToast.show(context, '暂无在线可打招呼用户');
        return;
      }
      AppToast.show(
        context,
        result.started
            ? '已开始发送，今日剩余 ${result.quota.remaining} 次'
            : '已发送 ${result.sentCount} 人，失败 ${result.failedCount} 人，今日剩余 ${result.quota.remaining} 次',
        backgroundColor: AppTheme.onlineGreen,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
      await ref.read(flirtGreetProvider.notifier).fetchQuota();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flirtUserListProvider);
    final greetState = ref.watch(flirtGreetProvider);
    final coinName = ref.watch(tokenNamesProvider).coinName;

    if (state.isLoading && state.users.isEmpty) {
      return StatusView.loading();
    }
    if (state.error != null && state.users.isEmpty) {
      return StatusView.error(
        message: state.error!,
        onRetry: () => ref.read(flirtUserListProvider.notifier).refresh(),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: state.users.isEmpty
            ? 2
            : state.users.length + 1 + (state.isLoading ? 1 : 0),
        separatorBuilder: (_, index) => state.users.isEmpty && index > 0
            ? const SizedBox.shrink()
            : const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _GreetingBar(state: greetState, onPressed: _sendGreeting);
          }
          final userIndex = index - 1;
          if (state.users.isEmpty) {
            return const SizedBox(
              height: 280,
              child: Center(
                child: Text(
                  '暂无可搭讪用户，可联系运营调整搭讪配置',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          if (userIndex >= state.users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _FlirtUserTile(
            user: state.users[userIndex],
            coinName: coinName,
          );
        },
      ),
    );
  }
}

class _GreetingBar extends StatelessWidget {
  final FlirtGreetState state;
  final VoidCallback onPressed;

  const _GreetingBar({required this.state, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final quota = state.quota;
    final disabled =
        state.isLoadingQuota ||
        state.isSending ||
        !quota.enabled ||
        quota.remaining <= 0 ||
        quota.cooldownSeconds > 0;
    final label = state.isSending
        ? '发送中'
        : !quota.enabled
        ? '打招呼功能已关闭'
        : quota.cooldownSeconds > 0
        ? '打招呼.${quota.cooldownSeconds}s'
        : '打招呼.今日剩余${quota.remaining}次';

    return SizedBox(
      width: double.infinity,
      height: 40,
      child: FilledButton.icon(
        onPressed: disabled ? null : onPressed,
        icon: state.isSending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.chat_bubble_outline, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: state.isSending
              ? Colors.black
              : AppTheme.cardBackground,
          disabledForegroundColor: state.isSending
              ? Colors.white
              : AppTheme.textSecondary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _FlirtUserTile extends StatelessWidget {
  final FlirtUserInfo user;
  final String coinName;

  const _FlirtUserTile({required this.user, required this.coinName});

  @override
  Widget build(BuildContext context) {
    final avatar = (user.avatar?.isNotEmpty ?? false)
        ? user.avatar!
        : (user.coverUrl ?? '');
    final statusColor = availabilityColor(user.availabilityStatus);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openDetail(context, user),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: avatar.isEmpty
                    ? const ColoredBox(
                        color: AppTheme.cardBackground,
                        child: Icon(
                          Icons.person,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    : Image.network(
                        avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                              color: AppTheme.cardBackground,
                              child: Icon(
                                Icons.person,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                      ),
              ),
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
                      child: Text(
                        user.username?.trim().isNotEmpty == true
                            ? user.username!.trim()
                            : '用户${user.userId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (user.isVip) ...[
                      const SizedBox(width: 4),
                      const VipBadge(dense: true),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.availabilityLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '金币余额 ${_formatCoins(user.coins)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 62,
                height: 32,
                child: OutlinedButton(
                  onPressed: () => _openIm(context, user),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: AppTheme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('文字'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 62,
                height: 32,
                child: FilledButton(
                  onPressed: () => _openCall(context, user),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('视频'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _openDetail(BuildContext context, FlirtUserInfo user) {
    context.push(
      Uri(
        path: AppRoutes.certifiedUserDetail,
        queryParameters: {'userId': user.userId.toString()},
      ).toString(),
    );
  }

  static void _openIm(BuildContext context, FlirtUserInfo user) {
    context.push(
      '${AppRoutes.im}/${user.userId}',
      extra: {'peerNickname': user.username, 'peerAvatarUrl': user.avatar},
    );
  }

  static void _openCall(BuildContext context, FlirtUserInfo user) {
    context.push(
      Uri(
        path: AppRoutes.callOutgoing,
        queryParameters: {
          'peerUserId': user.userId.toString(),
          'targetUserId': user.userId.toString(),
          'peerName': user.username ?? '用户${user.userId}',
          'peerAvatar': user.avatar ?? '',
          'peerIsVip': user.isVip ? '1' : '0',
          'callPrice': user.callPrice?.toStringAsFixed(0) ?? '0',
        },
      ).toString(),
    );
  }

  static String _formatCoins(double coins) {
    if (coins == coins.roundToDouble()) {
      return coins.toStringAsFixed(0);
    }
    return coins.toStringAsFixed(2);
  }
}
