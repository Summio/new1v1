import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../services/websocket_service.dart';
import 'call_end_reason.dart';

class CallOutgoingPage extends StatefulWidget {
  final int? callId;
  final String peerUserId;
  final String peerName;
  final String? peerAvatar;
  final String? anchorId;
  final int callPrice;

  const CallOutgoingPage({
    super.key,
    this.callId,
    required this.peerUserId,
    required this.peerName,
    this.peerAvatar,
    this.anchorId,
    required this.callPrice,
  });

  @override
  State<CallOutgoingPage> createState() => _CallOutgoingPageState();
}

class _CallOutgoingPageState extends State<CallOutgoingPage> {
  static const Duration _wsGracePeriod = Duration(seconds: 10);
  Timer? _countdownTimer;
  Timer? _wsDisconnectTimer;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;
  bool _pageClosing = false;
  bool _actionInFlight = false;
  bool _dialingInFlight = false;
  int _leftSeconds = 30;
  int? _callId;
  String _peerUserId = '';
  String _peerName = '';
  String? _peerAvatar;
  int _callPrice = 0;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId != null && widget.callId! > 0
        ? widget.callId
        : null;
    _peerUserId = widget.peerUserId;
    _peerName = widget.peerName;
    _peerAvatar = widget.peerAvatar;
    _callPrice = widget.callPrice;
    _leftSeconds = 30;

    _initWebSocket();

    if (_callId != null) {
      _startCountdown();
    } else {
      _startDialing();
    }
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
        _handleNetworkLost();
      });
    }
  }

  void _onWsEvent(WsEvent event) {
    if (!mounted || _pageClosing) return;

    final callId = _callId;
    if (callId == null || callId <= 0) return;

    final eventCallId = (event.data['call_id'] as num?)?.toInt();
    if (eventCallId == null || eventCallId != callId) return;

    if (event.event == 'call_accepted') {
      _goToCallRoom(callId);
      return;
    }

    const endedEvents = {
      'call_rejected',
      'call_timeout',
      'call_cancelled',
      'call_ended',
      'call_balance_empty',
    };
    if (endedEvents.contains(event.event)) {
      _closeWithReason(_reasonFromWsEvent(event));
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
      case 'call_rejected':
        return 'rejected';
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

  Future<void> _startDialing() async {
    if (_dialingInFlight || _pageClosing) return;
    final anchorId = int.tryParse((widget.anchorId ?? '').trim());
    if (anchorId == null || anchorId <= 0) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('主播参数异常，无法发起通话')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.index);
      }
      return;
    }

    _dialingInFlight = true;
    try {
      final dialingRes = await DioClient.instance.apiPost(
        ApiEndpoints.dialing,
        data: {'anchor_id': anchorId},
      );
      final dialingData = dialingRes['data'] as Map<String, dynamic>?;
      final callId = (dialingData?['call_id'] as num?)?.toInt();
      if (callId == null || callId <= 0) {
        throw const ApiException(code: 400, message: '呼叫创建失败，请稍后重试');
      }

      if (!mounted || _pageClosing) return;

      setState(() {
        _callId = callId;
        final peerUserId = (dialingData?['callee_id'] as num?)?.toInt();
        final peerName = (dialingData?['callee_nickname'] as String?)?.trim();
        final peerAvatar = (dialingData?['callee_avatar'] as String?)?.trim();
        final callPrice = (dialingData?['call_price'] as num?)?.toInt();
        if (peerUserId != null && peerUserId > 0) {
          _peerUserId = peerUserId.toString();
        }
        if (peerName != null && peerName.isNotEmpty) {
          _peerName = peerName;
        }
        if (peerAvatar != null && peerAvatar.isNotEmpty) {
          _peerAvatar = peerAvatar;
        }
        if (callPrice != null && callPrice >= 0) {
          _callPrice = callPrice;
        }
        final leftSeconds = (dialingData?['left_seconds'] as num?)?.toInt();
        if (leftSeconds != null && leftSeconds >= 0) {
          _leftSeconds = leftSeconds;
        }
      });
      _startCountdown();
    } on ApiException catch (e) {
      if (!mounted || _pageClosing) return;
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.index);
      }
    } catch (_) {
      if (!mounted || _pageClosing) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('通话启动失败，请稍后重试')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.index);
      }
    } finally {
      _dialingInFlight = false;
    }
  }

  void _goToCallRoom(int callId) {
    if (!mounted || _pageClosing) return;
    _pageClosing = true;
    _countdownTimer?.cancel();
    _wsDisconnectTimer?.cancel();
    context.pushReplacement(
      Uri(
        path: AppRoutes.callRoom,
        queryParameters: {
          'callId': callId.toString(),
          'peerUserId': _peerUserId,
          'anchorId': widget.anchorId,
          'peerName': _peerName,
        },
      ).toString(),
    );
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

  Future<void> _handleNetworkLost() async {
    if (!mounted || _pageClosing) return;
    final callId = _callId;
    if (callId != null && callId > 0) {
      try {
        await DioClient.instance.apiPost(
          ApiEndpoints.callCancel,
          data: {'call_id': callId},
        );
      } catch (_) {}
    }
    await _closeWithReason('network_lost');
  }

  Future<void> _cancelCall() async {
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      final callId = _callId;
      if (callId != null && callId > 0) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callCancel,
          data: {'call_id': callId},
        );
      }
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
        const SnackBar(content: Text('取消失败，请稍后重试')),
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
    final hasCallId = _callId != null && _callId! > 0;
    final countdownText = !hasCallId
        ? '正在发起呼叫...'
        : _callPrice > 0
        ? '$_leftSeconds 秒后自动结束 · $_callPrice/分'
        : '$_leftSeconds 秒后自动结束';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _cancelCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(
                hasCallId ? '视频呼叫中' : '正在连接',
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
                    (_peerAvatar != null && _peerAvatar!.isNotEmpty)
                    ? NetworkImage(_peerAvatar!)
                    : null,
                child: (_peerAvatar == null || _peerAvatar!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white70, size: 50)
                    : null,
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _peerName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                countdownText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              _ActionButton(
                color: AppTheme.errorColor,
                icon: Icons.call_end,
                label: '取消',
                onTap: _cancelCall,
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
