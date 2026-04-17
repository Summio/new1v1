import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';

/// 底部导航 Shell
/// 包含首页、发现、消息、我的四个标签
class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  Timer? _incomingTimer;
  Timer? _incomingAlertTimer;
  bool _incomingDialogShowing = false;
  int? _lastHandledCallId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  _IncomingCallPayload? _pendingIncomingWhenBackground;

  void _log(String message) {
    debugPrint('[INCOMING_FLOW] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startIncomingPolling();
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
      _tryShowPendingIncomingOnResume();
    }
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
    if (!auth.isLoggedIn || auth.appRole != 'anchor') {
      return;
    }

    if (_incomingDialogShowing) {
      return;
    }

    try {
      final res = await DioClient.instance.apiGet(ApiEndpoints.callIncoming);
      final data = res['data'];
      if (data is! Map<String, dynamic>) {
        _log('polling no incoming data');
        return;
      }

      final callId = (data['call_id'] as num?)?.toInt();
      final callerId = (data['caller_id'] as num?)?.toInt();
      final callerNickname = (data['caller_nickname'] as String?)?.trim() ?? '用户';
      final callerAvatar = (data['caller_avatar'] as String?)?.trim() ?? '';
      if (callId == null || callId <= 0 || callerId == null || callerId <= 0) {
        _log('polling invalid payload: $data');
        return;
      }
      if (_lastHandledCallId == callId) {
        _log('polling ignored duplicated callId=$callId');
        return;
      }
      _log('polling incoming callId=$callId callerId=$callerId lifecycle=$_lifecycleState');

      final payload = _IncomingCallPayload(
        callId: callId,
        callerId: callerId,
        callerNickname: callerNickname,
        callerAvatar: callerAvatar,
      );

      // 前台弹窗；后台仅缓存（通知占位）
      if (_lifecycleState == AppLifecycleState.resumed) {
        await _showIncomingDialog(payload, fromBackground: false);
      } else {
        _pendingIncomingWhenBackground = payload;
        _log('incoming received in background callId=$callId');
      }
    } catch (e) {
      _log('polling error: $e');
    }
  }

  Future<void> _tryShowPendingIncomingOnResume() async {
    if (_incomingDialogShowing) return;
    final pending = _pendingIncomingWhenBackground;
    if (pending == null) return;
    _pendingIncomingWhenBackground = null;
    await _showIncomingDialog(pending, fromBackground: true);
  }

  Future<void> _showIncomingDialog(
    _IncomingCallPayload payload, {
    required bool fromBackground,
  }) async {
    if (_incomingDialogShowing) return;
    if (_lastHandledCallId == payload.callId) return;
    if (!mounted) return;

    _incomingDialogShowing = true;
    _startIncomingAlert();
    try {
      if (fromBackground) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检测到后台来电，请尽快处理')),
        );
      }

      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('视频来电'),
          content: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEFEFF4),
                backgroundImage: payload.callerAvatar.isNotEmpty
                    ? NetworkImage(payload.callerAvatar)
                    : null,
                child: payload.callerAvatar.isEmpty
                    ? const Icon(Icons.person, color: AppTheme.textHint)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${payload.callerNickname} 邀请你视频通话'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'reject'),
              child: const Text('拒绝'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'accept'),
              child: const Text('接听'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (action == 'accept') {
        _log('dialog action accept callId=${payload.callId}');
        await DioClient.instance.apiPost(
          ApiEndpoints.callAccept,
          data: {'call_id': payload.callId},
        );
        if (!mounted) return;
        final callUri = Uri(
          path: AppRoutes.callRoom,
          queryParameters: {
            'callId': payload.callId.toString(),
            'peerUserId': payload.callerId.toString(),
            'peerName': payload.callerNickname,
          },
        );
        await context.push(
          callUri.toString(),
        );
      } else if (action == 'reject') {
        _log('dialog action reject callId=${payload.callId}');
        await DioClient.instance.apiPost(
          ApiEndpoints.callReject,
          data: {'call_id': payload.callId},
        );
      }

      _lastHandledCallId = payload.callId;
    } catch (e) {
      _log('dialog handling error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('处理来电失败，请重试')),
        );
      }
    } finally {
      _stopIncomingAlert();
      _incomingDialogShowing = false;
    }
  }

  void _startIncomingAlert() {
    _stopIncomingAlert();
    _incomingAlertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      SystemSound.play(SystemSoundType.alert);
      if (timer.tick.isEven) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopIncomingAlert() {
    _incomingAlertTimer?.cancel();
    _incomingAlertTimer = null;
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
        break;
      case 3:
        ref.read(authProvider.notifier).refreshBalance();
        context.go(AppRoutes.profile);
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingTimer?.cancel();
    _stopIncomingAlert();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

class _IncomingCallPayload {
  final int callId;
  final int callerId;
  final String callerNickname;
  final String callerAvatar;

  const _IncomingCallPayload({
    required this.callId,
    required this.callerId,
    required this.callerNickname,
    required this.callerAvatar,
  });
}

/// 导航项组件
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
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
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppTheme.primaryColor : AppTheme.textHint,
              size: 24,
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
