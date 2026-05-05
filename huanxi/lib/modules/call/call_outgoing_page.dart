import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/media_url.dart';
import '../../services/websocket_service.dart';
import 'call_end_reason.dart';
import 'call_event_mapper.dart';
import 'controllers/call_outgoing_controller.dart';

class CallOutgoingPage extends ConsumerStatefulWidget {
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
  ConsumerState<CallOutgoingPage> createState() => _CallOutgoingPageState();
}

class _CallOutgoingPageState extends ConsumerState<CallOutgoingPage> {
  static const Duration _wsGracePeriod = Duration(seconds: 10);

  Timer? _wsDisconnectTimer;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;
  bool _disposed = false;
  int? _callId;
  String _peerUserId = '';
  String _peerName = '';
  String? _peerAvatar;
  int _callPrice = 0;

  void _dismissTransientOverlays() {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    rootNavigator.popUntil((route) => route is PageRoute<dynamic>);
  }

  void _exitPage({Object? result}) {
    _dismissTransientOverlays();
    if (context.canPop()) {
      context.pop(result);
    } else {
      context.go(AppRoutes.index);
    }
  }

  @override
  void initState() {
    super.initState();
    _callId = widget.callId != null && widget.callId! > 0
        ? widget.callId
        : null;
    _peerUserId = widget.peerUserId;
    _peerName = widget.peerName;
    _peerAvatar = toAbsoluteMediaUrl(widget.peerAvatar);
    _callPrice = widget.callPrice;

    // 使用 Future.microtask 延迟执行，避免 widget build 阶段修改 provider
    Future.microtask(() {
      if (!mounted) return;
      ref.read(callOutgoingControllerProvider.notifier).setPageClosing(false);
      _initWebSocket();
      if (_callId != null) {
        ref
            .read(callOutgoingControllerProvider.notifier)
            .initCountdown(30, onTimeout: () => _closeWithReason('timeout'));
      } else {
        unawaited(_startDialing());
      }
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
    final ctrl = ref.read(callOutgoingControllerProvider);
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
        final current = ref.read(callOutgoingControllerProvider);
        if (!mounted ||
            current.isPageClosing ||
            WsService.instance.isConnected) {
          return;
        }
        unawaited(_handleNetworkLost());
      });
    }
  }

  void _onWsEvent(WsEvent event) {
    if (_disposed) return;
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;

    final callId = _callId;
    if (callId == null || callId <= 0) return;

    final eventCallId = (event.data['call_id'] as num?)?.toInt();
    if (eventCallId == null || eventCallId != callId) return;

    if (event.event == 'call_accepted') {
      _goToCallRoom(callId);
      return;
    }

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

  Future<void> _startDialing() async {
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (ctrl.isDialingInFlight || ctrl.isPageClosing) return;
    final anchorId =
        int.tryParse((widget.anchorId ?? '').trim()) ??
        int.tryParse(_peerUserId.trim());
    if (anchorId == null || anchorId <= 0) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('目标用户参数异常，无法发起通话')),
      );
      _exitPage();
      return;
    }

    ref.read(callOutgoingControllerProvider.notifier).setDialingInFlight(true);
    try {
      final dialingRes = await DioClient.instance.apiPost(
        ApiEndpoints.dialing,
        data: {'anchor_user_id': anchorId},
      );
      final dialingData = dialingRes['data'] as Map<String, dynamic>?;
      final callId = (dialingData?['call_id'] as num?)?.toInt();
      if (callId == null || callId <= 0) {
        throw const ApiException(code: 400, message: '呼叫创建失败，请稍后重试');
      }

      final current = ref.read(callOutgoingControllerProvider);
      if (!mounted || current.isPageClosing) return;

      setState(() {
        _callId = callId;
        final peerUserId = (dialingData?['callee_id'] as num?)?.toInt();
        final peerName = (dialingData?['callee_nickname'] as String?)?.trim();
        final peerAvatar = toAbsoluteMediaUrl(
          (dialingData?['callee_avatar'] as String?)?.trim(),
        );
        final callPrice = (dialingData?['call_price'] as num?)?.toInt();
        if (peerUserId != null && peerUserId > 0) {
          _peerUserId = peerUserId.toString();
        }
        if (peerName != null && peerName.isNotEmpty) {
          _peerName = peerName;
        }
        if (peerAvatar.isNotEmpty) {
          _peerAvatar = peerAvatar;
        }
        if (callPrice != null && callPrice >= 0) {
          _callPrice = callPrice;
        }
      });
      final leftSeconds = (dialingData?['left_seconds'] as num?)?.toInt() ?? 30;
      ref
          .read(callOutgoingControllerProvider.notifier)
          .initCountdown(
            leftSeconds,
            onTimeout: () => _closeWithReason('timeout'),
          );
    } on ApiException catch (e) {
      final current = ref.read(callOutgoingControllerProvider);
      if (!mounted || current.isPageClosing) return;
      _closeWithDialingError(e.message);
    } catch (_) {
      final current = ref.read(callOutgoingControllerProvider);
      if (!mounted || current.isPageClosing) return;
      _closeWithDialingError('通话启动失败，请稍后重试');
    } finally {
      if (mounted) {
        ref
            .read(callOutgoingControllerProvider.notifier)
            .setDialingInFlight(false);
      }
    }
  }

  void _closeWithDialingError(String message) {
    final normalized = AppToast.normalizeMessage(message);
    _exitPage(result: normalized);
  }

  void _goToCallRoom(int callId) {
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;
    ref.read(callOutgoingControllerProvider.notifier).setPageClosing(true);
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
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;
    ref.read(callOutgoingControllerProvider.notifier).setPageClosing(true);
    _wsDisconnectTimer?.cancel();
    AppToast.showSnackBar(
      context,
      SnackBar(content: Text(callEndReasonText(reason))),
    );
    _exitPage();
  }

  Future<void> _handleNetworkLost() async {
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (!mounted || ctrl.isPageClosing) return;
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
    final ctrl = ref.read(callOutgoingControllerProvider);
    if (ctrl.isActionInFlight || ctrl.isPageClosing) return;
    ref.read(callOutgoingControllerProvider.notifier).setActionInFlight(true);
    try {
      final callId = _callId;
      if (callId != null && callId > 0) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callCancel,
          data: {'call_id': callId},
        );
      }
      if (!mounted) return;
      ref.read(callOutgoingControllerProvider.notifier).setPageClosing(true);
      _wsDisconnectTimer?.cancel();
      _exitPage();
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('取消失败，请稍后重试')),
      );
    } finally {
      if (mounted) {
        ref
            .read(callOutgoingControllerProvider.notifier)
            .setActionInFlight(false);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wsDisconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outgoingState = ref.watch(callOutgoingControllerProvider);
    final hasCallId = _callId != null && _callId! > 0;
    final countdownText = !hasCallId
        ? '正在发起呼叫...'
        : _callPrice > 0
        ? '${outgoingState.leftSeconds} 秒后自动结束 · $_callPrice/分'
        : '${outgoingState.leftSeconds} 秒后自动结束';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_cancelCall());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      ? const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 50,
                        )
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
                  label: outgoingState.isActionInFlight ? '处理中...' : '取消',
                  onTap: _cancelCall,
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
