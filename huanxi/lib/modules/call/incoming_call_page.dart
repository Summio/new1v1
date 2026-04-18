import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../services/websocket_service.dart';
import 'call_end_reason.dart';

class IncomingCallPage extends StatefulWidget {
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
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  static const Duration _wsGracePeriod = Duration(seconds: 10);
  Timer? _countdownTimer;
  Timer? _wsDisconnectTimer;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;
  bool _actionInFlight = false;
  bool _pageClosing = false;
  int _leftSeconds = 30;

  @override
  void initState() {
    super.initState();
    _leftSeconds = widget.leftSeconds > 0 ? widget.leftSeconds : 30;
    _initWebSocket();
    _startCountdown();
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
    if (!mounted || _pageClosing) return;

    if (event.state == WsConnectionState.connected) {
      _wsDisconnectTimer?.cancel();
      _wsDisconnectTimer = null;
      return;
    }

    if (event.state == WsConnectionState.reconnecting ||
        event.state == WsConnectionState.disconnected ||
        event.state == WsConnectionState.authFailed) {
      _wsDisconnectTimer ??= Timer(_wsGracePeriod, () {
        if (!mounted || _pageClosing || WsService.instance.isConnected) return;
        _closeWithReason('network_lost');
      });
    }
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted || _pageClosing) return;
    final eventCallId = (event.data['call_id'] as num?)?.toInt();
    if (eventCallId == null || eventCallId != widget.callId) return;

    switch (event.event) {
      case 'call_cancelled':
      case 'call_timeout':
      case 'call_ended':
      case 'call_balance_empty':
        _closeWithReason(_reasonFromWsEvent(event));
        break;
      default:
        break;
    }
  }

  String _reasonFromWsEvent(WsEvent event) {
    final reasonFromData = (event.data['end_reason'] as String?)?.trim();
    if (reasonFromData != null && reasonFromData.isNotEmpty) {
      return reasonFromData;
    }
    final reasonFromEvent = (event.data['reason'] as String?)?.trim();
    if (reasonFromEvent != null && reasonFromEvent.isNotEmpty) {
      return reasonFromEvent;
    }

    switch (event.event) {
      case 'call_timeout':
        return 'timeout';
      case 'call_cancelled':
        return 'cancelled';
      case 'call_balance_empty':
        return 'balance_empty';
      default:
        return 'normal';
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_leftSeconds <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _pageClosing) {
        timer.cancel();
        return;
      }
      if (_leftSeconds <= 0) {
        timer.cancel();
        _closeWithReason('timeout');
        return;
      }
      setState(() => _leftSeconds -= 1);
    });
  }

  Future<void> _closeWithReason(String reason) async {
    if (!mounted || _pageClosing) return;
    _pageClosing = true;
    _countdownTimer?.cancel();
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
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callAccept,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      _pageClosing = true;
      _countdownTimer?.cancel();
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
      _actionInFlight = false;
    }
  }

  Future<void> _rejectCall() async {
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callReject,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      _pageClosing = true;
      _countdownTimer?.cancel();
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
      _actionInFlight = false;
    }
  }

  @override
  void dispose() {
    _pageClosing = true;
    _countdownTimer?.cancel();
    _wsDisconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
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
                '$_leftSeconds 秒后自动挂断',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ActionButton(
                      color: AppTheme.errorColor,
                      icon: Icons.call_end,
                      label: '拒绝',
                      onTap: _rejectCall,
                    ),
                    _ActionButton(
                      color: const Color(0xFF22C55E),
                      icon: Icons.call,
                      label: '接听',
                      onTap: _acceptCall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),
            ],
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
