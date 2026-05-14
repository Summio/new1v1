import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/providers/flirt_user_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flirtUserListProvider);
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
      onRefresh: () => ref.read(flirtUserListProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: state.users.isEmpty
            ? 1
            : state.users.length + (state.isLoading ? 1 : 0),
        separatorBuilder: (_, index) => state.users.isEmpty
            ? const SizedBox.shrink()
            : const SizedBox(height: 10),
        itemBuilder: (context, index) {
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
          if (index >= state.users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _FlirtUserTile(user: state.users[index], coinName: coinName);
        },
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: avatar.isEmpty
                  ? const ColoredBox(
                      color: AppTheme.cardBackground,
                      child: Icon(Icons.person, color: AppTheme.textSecondary),
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
                const SizedBox(height: 6),
                Text(
                  '${_genderText(user.gender)} · ${_locationText(user.locationCity)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
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
          'callPrice': user.callPrice?.toStringAsFixed(0) ?? '0',
        },
      ).toString(),
    );
  }

  static String _genderText(String? gender) {
    if (gender == 'female') return '女';
    if (gender == 'male') return '男';
    return '未知';
  }

  static String _locationText(String? locationCity) {
    final value = locationCity?.trim() ?? '';
    return value.isEmpty ? '所在地未填' : value;
  }

  static String _formatCoins(double coins) {
    if (coins == coins.roundToDouble()) {
      return coins.toStringAsFixed(0);
    }
    return coins.toStringAsFixed(2);
  }
}
