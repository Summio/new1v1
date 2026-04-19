import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../services/websocket_service.dart';
import 'call_end_reason.dart';
import 'call_event_mapper.dart';
import 'controllers/call_incoming_controller.dart';

class IncomingCallPage extends ConsumerStatefulWidget {
  final int callId;
  final String peerUserId;
  final String peerName;
  final String? peerAvatar;
  final int leftSeconds;

  const IncomingCallPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    this.peerAvatar,
    this.leftSeconds = 30,
  });

  @override
  ConsumerState<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends ConsumerState<IncomingCallPage> {
  static const Duration _wsGracePeriod = Duration(seconds: 10);
  Timer? _wsDisconnectTimer;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final initLeft = widget.leftSeconds > 0 ? widget.leftSeconds : 30;
    // 使用 Future.microtask 延迟执行，避免 widget build 阶段修改 provider
    Future.microtask(() {
      if (!mounted) return;
      ref.read(callIncomingControllerProvider.notifier).setPageClosing(false);
      ref
          .read(callIncomingControllerProvider.notifier)
          .initCountdown(initLeft, onTimeout: () => _closeWithReason('timeout'));
      _initWebSocket();
    });
  }

  void _initWebSocket() {
    WsService.instance.connect();
    _wsSubscription?.cancel();
    _wsSubscription = WsService.instance.events.listen(_onWsEvent);
    _wsConnectionSubscription?.cancel();
    _wsConnectionSubscription = WsService.instance.connectionEvents.listen(
      _onWsConnectionEvent,
    );
  }

  void _onWsConnectionEvent(WsConnectionEvent event) {
    if (_disposed) return;
    final ctrl = ref.read(callIncomingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;

    if (event.state == WsConnectionState.connected) {
      _wsDisconnectTimer?.cancel();
      _wsDisconnectTimer = null;
      return;
    }

    if (event.state == WsConnectionState.reconnecting ||
        event.state == WsConnectionState.disconnected ||
        event.state == WsConnectionState.authFailed) {
      _wsDisconnectTimer ??= Timer(_wsGracePeriod, () {
        final current = ref.read(callIncomingControllerProvider);
        if (!mounted || current.isPageClosing || WsService.instance.isConnected) {
          return;
        }
        unawaited(_closeWithReason('network_lost'));
      });
    }
  }

  void _onWsEvent(WsEvent event) {
    if (_disposed) return;
    final ctrl = ref.read(callIncomingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;
    final eventCallId = (event.data['call_id'] as num?)?.toInt();
    if (eventCallId == null || eventCallId != widget.callId) return;
    final mapped = CallEventMapper.map(event: event.event, data: event.data);
    if (mapped.shouldExit) {
      unawaited(_closeWithReason(_reasonFromMapped(mapped.endReason)));
    }
  }

  String _reasonFromMapped(CallEndReason? reason) {
    switch (reason) {
      case CallEndReason.rejected:
        return 'rejected';
      case CallEndReason.timeout:
        return 'timeout';
      case CallEndReason.cancelled:
        return 'cancelled';
      case CallEndReason.balanceEmpty:
        return 'balance_empty';
      case CallEndReason.forceExit:
        return 'force_exit';
      case CallEndReason.peerLeft:
        return 'peer_left';
      case CallEndReason.networkLost:
        return 'network_lost';
      case CallEndReason.normal:
      case null:
        return 'normal';
    }
  }

  Future<void> _closeWithReason(String reason) async {
    final ctrl = ref.read(callIncomingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;
    ref.read(callIncomingControllerProvider.notifier).setPageClosing(true);
    _wsDisconnectTimer?.cancel();
    AppToast.showSnackBar(
      context,
      SnackBar(content: Text(callEndReasonText(reason))),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.index);
    }
  }

  Future<void> _acceptCall() async {
    final ctrl = ref.read(callIncomingControllerProvider);
    if (ctrl.isActionInFlight || ctrl.isPageClosing) return;
    ref.read(callIncomingControllerProvider.notifier).setActionInFlight(true);
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callAccept,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      ref.read(callIncomingControllerProvider.notifier).setPageClosing(true);
      _wsDisconnectTimer?.cancel();
      context.pushReplacement(
        Uri(
          path: AppRoutes.callRoom,
          queryParameters: {
            'callId': widget.callId.toString(),
            'peerUserId': widget.peerUserId,
            'peerName': widget.peerName,
          },
        ).toString(),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('接听失败，请重试')),
      );
    } finally {
      ref.read(callIncomingControllerProvider.notifier).setActionInFlight(false);
    }
  }

  Future<void> _rejectCall() async {
    final ctrl = ref.read(callIncomingControllerProvider);
    if (ctrl.isActionInFlight || ctrl.isPageClosing) return;
    ref.read(callIncomingControllerProvider.notifier).setActionInFlight(true);
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callReject,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      ref.read(callIncomingControllerProvider.notifier).setPageClosing(true);
      _wsDisconnectTimer?.cancel();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.index);
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('拒绝失败，请重试')),
      );
    } finally {
      ref.read(callIncomingControllerProvider.notifier).setActionInFlight(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ref.read(callIncomingControllerProvider.notifier).setPageClosing(true);
    _wsDisconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incomingState = ref.watch(callIncomingControllerProvider);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Text(
                  '视频来电',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white12,
                  backgroundImage:
                      (widget.peerAvatar != null && widget.peerAvatar!.isNotEmpty)
                      ? NetworkImage(widget.peerAvatar!)
                      : null,
                  child:
                      (widget.peerAvatar == null || widget.peerAvatar!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white70, size: 50)
                      : null,
                ),
                const SizedBox(height: 18),
                Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${incomingState.leftSeconds} 秒后自动挂断',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      color: AppTheme.errorColor,
                      icon: Icons.call_end,
                      label: incomingState.isActionInFlight ? '处理中...' : '拒绝',
                      onTap: _rejectCall,
                    ),
                    _ActionButton(
                      color: AppTheme.onlineGreen,
                      icon: Icons.call,
                      label: incomingState.isActionInFlight ? '处理中...' : '接听',
                      onTap: _acceptCall,
                    ),
                  ],
                ),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
