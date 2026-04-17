import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/storage/storage.dart';
import '../../services/im_service.dart';
import '../call/call_session_payload.dart';

/// 底部导航 Shell
/// 包含首页、发现、消息、我的四个标签
class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  Timer? _incomingTimer;
  final IMService _imService = IMService();
  bool _incomingPageShowing = false;
  int? _lastHandledCallId;
  int _imUnreadCount = 0;
  void Function(int)? _imUnreadListener;
  Function(dynamic)? _imMessageListener;
  bool _isInitGlobalIMUnreadRunning = false;
  int? _imReadyUserId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  CallSessionPayload? _pendingIncomingWhenBackground;

  void _log(String message) {
    debugPrint('[INCOMING_FLOW] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startIncomingPolling();
    _initGlobalIMUnread();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(authProvider.notifier).refreshBalance();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).refreshBalance();
      _openPendingIncomingOnResume();
      if (_imService.isInitialized) {
        _refreshUnreadCount();
      } else {
        _initGlobalIMUnread();
      }
    }
  }

  Future<void> _initGlobalIMUnread() async {
    if (_isInitGlobalIMUnreadRunning) {
      return;
    }
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      _imReadyUserId = null;
      if (mounted && _imUnreadCount != 0) {
        setState(() => _imUnreadCount = 0);
      }
      return;
    }

    final userId = auth.userId ?? StorageService.getUserId();
    if (userId == null || userId <= 0) {
      return;
    }
    if (_imReadyUserId == userId && _imService.isInitialized) {
      return;
    }

    _isInitGlobalIMUnreadRunning = true;
    try {
      final sigRes = await DioClient.instance.get(ApiEndpoints.imUserSig);
      final payload = ResponseParsers.parseUserSigPayload(sigRes.data);
      await _imService.ensureReady(
        sdkAppId: payload.sdkAppId,
        userId: 'chat_$userId',
        userSig: payload.userSig,
      );

      _imUnreadListener ??= _onImTotalUnreadChanged;
      _imService.removeTotalUnreadListener(_imUnreadListener!);
      _imService.addTotalUnreadListener(_imUnreadListener!);
      _imMessageListener ??= _onImMessageReceived;
      _imService.removeMessageListener(_imMessageListener!);
      _imService.addMessageListener(_imMessageListener!);
      _imReadyUserId = userId;
      await _refreshUnreadCount();
    } catch (e) {
      debugPrint('mainShell.initGlobalIMUnread error: $e');
    } finally {
      _isInitGlobalIMUnreadRunning = false;
    }
  }

  Future<void> _refreshUnreadCount() async {
    if (!_imService.isInitialized) {
      return;
    }
    try {
      final total = await _imService.getTotalUnreadCount();
      _onImTotalUnreadChanged(total);
    } catch (e) {
      debugPrint('mainShell.refreshUnreadCount error: $e');
    }
  }

  void _onImTotalUnreadChanged(int totalUnread) {
    final next = totalUnread < 0 ? 0 : totalUnread;
    debugPrint('[IM_UNREAD] 未读数变化: $_imUnreadCount -> $next');
    if (!mounted || next == _imUnreadCount) {
      return;
    }
    setState(() {
      _imUnreadCount = next;
    });
  }

  void _onImMessageReceived(dynamic _) {
    debugPrint('[IM_UNREAD] 收到新消息，主动刷新未读数 (第1次)');
    _refreshUnreadCount();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _imService.isInitialized) {
        debugPrint('[IM_UNREAD] 延迟刷新未读数 (第2次确认)');
        _refreshUnreadCount();
      }
    });
  }

  void _startIncomingPolling() {
    _incomingTimer?.cancel();
    _incomingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkIncomingCall();
    });
    _checkIncomingCall();
  }

  Future<void> _checkIncomingCall() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.appRole != 'anchor' || _incomingPageShowing) {
      return;
    }

    try {
      final res = await DioClient.instance.apiGet(ApiEndpoints.callSessionCurrent);
      final payload = CallSessionPayload.fromJson(
        res['data'] is Map<String, dynamic>
            ? res['data'] as Map<String, dynamic>
            : null,
      );

      if (!payload.isPending || payload.role != 'callee') {
        return;
      }

      final callId = payload.callId;
      final peerUserId = payload.peerUserId;
      if (callId == null || callId <= 0 || peerUserId == null || peerUserId <= 0) {
        return;
      }
      if (_lastHandledCallId == callId) {
        _log('polling ignored duplicated callId=$callId');
        return;
      }
      _log(
        'polling incoming callId=$callId peerUserId=$peerUserId lifecycle=$_lifecycleState',
      );

      if (_lifecycleState == AppLifecycleState.resumed) {
        await _openIncomingCallPage(payload);
      } else {
        _pendingIncomingWhenBackground = payload;
        _log('incoming received in background callId=$callId');
      }
    } catch (e) {
      _log('polling error: $e');
    }
  }

  Future<void> _openPendingIncomingOnResume() async {
    if (_incomingPageShowing) return;
    final pending = _pendingIncomingWhenBackground;
    if (pending == null) return;
    _pendingIncomingWhenBackground = null;
    await _openIncomingCallPage(pending);
  }

  Future<void> _openIncomingCallPage(CallSessionPayload payload) async {
    if (_incomingPageShowing) return;
    if (_lastHandledCallId == payload.callId) return;
    if (!mounted || payload.callId == null || payload.peerUserId == null) return;

    _incomingPageShowing = true;
    try {
      final callUri = Uri(
        path: AppRoutes.callIncoming,
        queryParameters: {
          'callId': payload.callId.toString(),
          'peerUserId': payload.peerUserId.toString(),
          'peerName': payload.peerNickname,
          'peerAvatar': payload.peerAvatar ?? '',
        },
      );
      await context.push(callUri.toString());
      _lastHandledCallId = payload.callId;
    } catch (e) {
      _log('open incoming page error: $e');
    } finally {
      _incomingPageShowing = false;
    }
  }

  int _getCurrentIndex(BuildContext context) {
    try {
      final location = GoRouterState.of(context).matchedLocation;
      if (location.startsWith(AppRoutes.index)) return 0;
      if (location.startsWith(AppRoutes.discover)) return 1;
      if (location.startsWith(AppRoutes.messages)) return 2;
      if (location.startsWith(AppRoutes.profile)) return 3;
    } catch (e) {
      debugPrint('mainShell.getCurrentIndex error: $e');
    }
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.index);
        break;
      case 1:
        context.go(AppRoutes.discover);
        break;
      case 2:
        context.go(AppRoutes.messages);
        _refreshUnreadCount();
        break;
      case 3:
        ref.read(authProvider.notifier).refreshBalance();
        context.go(AppRoutes.profile);
        break;
    }
  }

  @override
  void dispose() {
    if (_imUnreadListener != null) {
      _imService.removeTotalUnreadListener(_imUnreadListener!);
    }
    if (_imMessageListener != null) {
      _imService.removeMessageListener(_imMessageListener!);
    }
    WidgetsBinding.instance.removeObserver(this);
    _incomingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final currentUserId = auth.userId ?? StorageService.getUserId();
    final shouldEnsureGlobalImReady =
        auth.isLoggedIn &&
        currentUserId != null &&
        (!_imService.isInitialized || _imReadyUserId != currentUserId);
    if (shouldEnsureGlobalImReady && !_isInitGlobalIMUnreadRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _initGlobalIMUnread();
      });
    }

    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: '首页',
                  isActive: currentIndex == 0,
                  onTap: () => _onTap(context, 0),
                ),
                _NavItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: '发现',
                  isActive: currentIndex == 1,
                  onTap: () => _onTap(context, 1),
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: '消息',
                  isActive: currentIndex == 2,
                  badgeCount: _imUnreadCount,
                  onTap: () => _onTap(context, 2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: '我的',
                  isActive: currentIndex == 3,
                  onTap: () => _onTap(context, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 导航项组件
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Icon(
                      isActive ? activeIcon : icon,
                      color: isActive
                          ? AppTheme.primaryColor
                          : AppTheme.textHint,
                      size: 24,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -3,
                      child: _UnreadBadge(count: badgeCount),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? AppTheme.primaryColor : AppTheme.textHint,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
