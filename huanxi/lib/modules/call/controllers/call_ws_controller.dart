import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/auth_provider.dart';
import '../../../services/websocket_service.dart';
import '../call_event_mapper.dart';
import 'call_gift_controller.dart';
import 'call_session_controller.dart';

class CallWsState {
  final bool connected;
  final bool networkLost;
  final CallMappedEvent? lastMappedEvent;
  final int balanceLowNoticeSeq;

  const CallWsState({
    this.connected = false,
    this.networkLost = false,
    this.lastMappedEvent,
    this.balanceLowNoticeSeq = 0,
  });

  CallWsState copyWith({
    bool? connected,
    bool? networkLost,
    CallMappedEvent? lastMappedEvent,
    int? balanceLowNoticeSeq,
  }) {
    return CallWsState(
      connected: connected ?? this.connected,
      networkLost: networkLost ?? this.networkLost,
      lastMappedEvent: lastMappedEvent ?? this.lastMappedEvent,
      balanceLowNoticeSeq: balanceLowNoticeSeq ?? this.balanceLowNoticeSeq,
    );
  }
}

class CallWsController extends StateNotifier<CallWsState> {
  CallWsController(this._ref, {required this.callId})
    : super(const CallWsState());

  static const Duration _wsGracePeriod = Duration(seconds: 10);

  final Ref _ref;
  final int callId;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;
  Timer? _wsDisconnectTimer;
  DateTime? _lastBalanceLowNoticeAt;

  void bind() {
    WsService.instance.connect();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();

    _wsSubscription = WsService.instance.events.listen((event) {
      final mapped = CallEventMapper.map(event: event.event, data: event.data);
      state = state.copyWith(lastMappedEvent: mapped);

      if (mapped.shouldSyncBalance) {
        final coins = _asDouble(event.data['coins']);
        final diamonds = _asDouble(event.data['diamonds']);
        if (coins != null || diamonds != null) {
          _ref
              .read(authProvider.notifier)
              .syncBalance(coins: coins, diamonds: diamonds);
        }
        return;
      }

      if (mapped.shouldShowGift) {
        final scene = (event.data['scene'] as String?) ?? 'chat';
        if (scene != 'call') {
          return;
        }
        final eventCallId = _asInt(event.data['call_id']);
        if (eventCallId != callId) {
          return;
        }
        final quantity = _asInt(event.data['quantity']) ?? 1;
        final giftPrice = _asInt(event.data['gift_price']) ?? 0;
        final totalPrice =
            _asInt(event.data['total_price']) ?? (giftPrice * quantity);
        _ref
            .read(callGiftControllerProvider(callId).notifier)
            .showGift(
              giftName: event.data['gift_name'] as String? ?? '',
              giftIcon: event.data['gift_icon'] as String? ?? '',
              svgaUrl: event.data['svga_url'] as String? ?? '',
              giftPrice: giftPrice,
              quantity: quantity,
              totalPrice: totalPrice,
              scene: scene,
              callId: eventCallId,
              senderNickname: event.data['sender_nickname'] as String? ?? '用户',
            );
        return;
      }

      if (mapped.shouldShowBalanceLow) {
        final eventCallId = _asInt(event.data['call_id']);
        if (eventCallId != callId) {
          return;
        }
        final coins = _asDouble(event.data['coins']);
        if (coins != null) {
          _ref.read(authProvider.notifier).syncBalance(coins: coins);
        }
        final now = DateTime.now();
        final lastNoticeAt = _lastBalanceLowNoticeAt;
        if (lastNoticeAt == null ||
            now.difference(lastNoticeAt) >= const Duration(seconds: 10)) {
          _lastBalanceLowNoticeAt = now;
          state = state.copyWith(
            balanceLowNoticeSeq: state.balanceLowNoticeSeq + 1,
          );
        }
        return;
      }

      if (!mapped.shouldExit) {
        return;
      }

      final eventCallId = _asInt(event.data['call_id']);
      if (eventCallId != callId) {
        debugPrint(
          '[CallWs] 收到事件 ${event.event} 但 call_id 不匹配: '
          'eventCallId=$eventCallId, expected=$callId',
        );
        return;
      }
      debugPrint('[CallWs] 收到通话结束事件，开始结束通话');
      final endReason = _mapEndReasonToString(mapped.endReason);
      _ref
          .read(callSessionProvider(callId).notifier)
          .beginEnding(
            endReason: endReason,
            notifyEndApi: false,
            endingForBalance: endReason == 'balance_empty',
          );
    });

    _wsConnectionSubscription = WsService.instance.connectionEvents.listen((
      event,
    ) {
      if (event.state == WsConnectionState.connected) {
        _wsDisconnectTimer?.cancel();
        _wsDisconnectTimer = null;
        state = state.copyWith(connected: true, networkLost: false);
        return;
      }

      if (event.state == WsConnectionState.reconnecting ||
          event.state == WsConnectionState.disconnected ||
          event.state == WsConnectionState.authFailed) {
        state = state.copyWith(connected: false);
        _wsDisconnectTimer ??= Timer(_wsGracePeriod, () {
          if (WsService.instance.isConnected) {
            return;
          }
          state = state.copyWith(networkLost: true);
          _ref
              .read(callSessionProvider(callId).notifier)
              .beginEnding(endReason: 'network_lost', notifyEndApi: true);
        });
      }
    });
  }

  void unbind() {
    _wsDisconnectTimer?.cancel();
    _wsDisconnectTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsConnectionSubscription?.cancel();
    _wsConnectionSubscription = null;
  }

  String _mapEndReasonToString(CallEndReason? reason) {
    switch (reason) {
      case CallEndReason.rejected:
        return 'rejected';
      case CallEndReason.timeout:
        return 'timeout';
      case CallEndReason.cancelled:
        return 'cancelled';
      case CallEndReason.balanceEmpty:
        return 'balance_empty';
      case CallEndReason.networkLost:
        return 'network_lost';
      case CallEndReason.peerLeft:
        return 'peer_left';
      case CallEndReason.forceExit:
        return 'force_exit';
      case CallEndReason.normal:
      case null:
        return 'normal';
    }
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

final callWsControllerProvider = StateNotifierProvider.autoDispose
    .family<CallWsController, CallWsState, int>(
      (ref, callId) => CallWsController(ref, callId: callId),
    );
