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
import '../../services/websocket_service.dart';
import '../call/call_session_payload.dart';

/// 底部导航 Shell
/// 包含首页、发现、消息、我的四个标签
class MainShell extends ConsumerStatefulWidget {
  static final _presenceStreamController =
      StreamController<PresenceEvent>.broadcast();

  /// 在线状态变化事件流（其他页面可监听此 stream 刷新 UI）
  static Stream<PresenceEvent> get presenceStream =>
      _presenceStreamController.stream;

  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

/// WebSocket 在线状态变化事件
class PresenceEvent {
  final int userId;
  final bool online;
  const PresenceEvent({required this.userId, required this.online});
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  final IMService _imService = IMService();
  bool _incomingPageShowing = false;
  String? _lastHandledIncomingKey;
  int _imUnreadCount = 0;
  void Function(int)? _imUnreadListener;
  Function(dynamic)? _imMessageListener;
  bool _isInitGlobalIMUnreadRunning = false;
  int? _imReadyUserId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  CallSessionPayload? _pendingIncomingWhenBackground;
  String? _lastMatchedLocation;
  StreamSubscription<WsEvent>? _wsSubscription;

  void _log(String message) {
    debugPrint('[INCOMING_FLOW] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGlobalIMUnread();
    _initWebSocket();
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
      WsService.instance.connect();
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
      await _imService.syncTotalUnreadCount();
    } catch (e) {
      debugPrint('mainShell.refreshUnreadCount error: $e');
    }
  }

  String? _currentMatchedLocation(BuildContext context) {
    try {
      return GoRouterState.of(context).matchedLocation;
    } catch (_) {
      return null;
    }
  }

  bool _isImRoute(String? location) {
    if (location == null || location.isEmpty) {
      return false;
    }
    return location.startsWith(AppRoutes.im);
  }

  void _handleRouteBasedUnreadRefresh(String currentLocation) {
    final previous = _lastMatchedLocation;
    _lastMatchedLocation = currentLocation;
    if (_isImRoute(previous) &&
        currentLocation.startsWith(AppRoutes.messages)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshUnreadCount();
      });
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

  String? _incomingDedupKey(CallSessionPayload payload) {
    final callId = payload.callId;
    if (callId == null || callId <= 0) return null;
    final createdAt = payload.createdAt?.trim();
    if (createdAt != null && createdAt.isNotEmpty) {
      return '$callId|$createdAt';
    }
    // 兜底：服务端缺失 created_at 时，使用稳定字段去重，避免 key 抖动
    return '$callId|${payload.peerUserId ?? 0}|${payload.role ?? ''}';
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
    final dedupKey = _incomingDedupKey(payload);
    if (dedupKey != null && _lastHandledIncomingKey == dedupKey) return;
    if (!mounted || payload.callId == null || payload.peerUserId == null) {
      return;
    }

    _incomingPageShowing = true;
    _lastHandledIncomingKey = dedupKey;
    try {
      final callUri = Uri(
        path: AppRoutes.callIncoming,
        queryParameters: {
          'callId': payload.callId.toString(),
          'peerUserId': payload.peerUserId.toString(),
          'peerName': payload.peerNickname,
          'peerAvatar': payload.peerAvatar ?? '',
          'leftSeconds': payload.leftSeconds.toString(),
        },
      );
      await context.push(callUri.toString());
    } catch (e) {
      _log('open incoming page error: $e');
    } finally {
      _incomingPageShowing = false;
    }
  }

  // ===== WebSocket 事件监听 =====

  void _initWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = WsService.instance.events.listen(_onWsEvent);
    // 已登录则立即连接
    if (ref.read(authProvider).isLoggedIn) {
      WsService.instance.connect();
    }
  }

  void _onWsEvent(WsEvent event) {
    switch (event.event) {
      case 'balance_updated':
        _handleBalanceUpdated(event.data);
        break;
      case 'call_incoming':
        _handleWsIncomingCall(event.data);
        break;
      case 'presence':
        _handlePresenceEvent(event.data);
        break;
    }
  }

  void _handleBalanceUpdated(Map<String, dynamic> data) {
    final coins = data['coins'] as int?;
    final diamonds = data['diamonds'] as int?;
    if (coins != null || diamonds != null) {
      ref
          .read(authProvider.notifier)
          .syncBalance(
            coins: coins ?? ref.read(authProvider).coins,
            diamonds: diamonds ?? ref.read(authProvider).diamonds,
          );
    }
  }

  void _handleWsIncomingCall(Map<String, dynamic> data) {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.appRole != 'anchor' || _incomingPageShowing) {
      return;
    }
    try {
      // WebSocket call_incoming 事件字段映射：
      // 后端发送: caller_id, caller_name, caller_avatar, call_price, left_seconds
      // CallSessionPayload 期望: peer_user_id, peer_nickname, peer_avatar, ...
      // 加上 status=pending 和 role=callee（来电场景固定为被叫）
      final wsData = Map<String, dynamic>.from(data);
      wsData['peer_user_id'] = wsData['caller_id'];
      wsData['peer_nickname'] = wsData['caller_name'] ?? '用户';
      wsData['peer_avatar'] = wsData['caller_avatar'];
      wsData['status'] = 'pending';
      wsData['role'] = 'callee';

      final payload = CallSessionPayload.fromJson(wsData);
      if (!payload.isPending) return;

      final callId = payload.callId;
      final peerUserId = payload.peerUserId;
      if (callId == null ||
          callId <= 0 ||
          peerUserId == null ||
          peerUserId <= 0) {
        return;
      }

      _log('[WS] 收到来电事件 callId=$callId peerUserId=$peerUserId');

      if (_lifecycleState == AppLifecycleState.resumed) {
        _openIncomingCallPage(payload);
      } else {
        _pendingIncomingWhenBackground = payload;
      }
    } catch (e) {
      _log('[WS] 来电事件解析失败: $e');
    }
  }

  void _handlePresenceEvent(Map<String, dynamic> data) {
    final userId = data['user_id'] as int?;
    final online = data['online'] as bool?;
    if (userId == null || online == null) return;
    MainShell._presenceStreamController.add(
      PresenceEvent(userId: userId, online: online),
    );
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
    _wsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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

    final currentLocation = _currentMatchedLocation(context) ?? '';
    if (currentLocation.isNotEmpty) {
      _handleRouteBasedUnreadRefresh(currentLocation);
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
