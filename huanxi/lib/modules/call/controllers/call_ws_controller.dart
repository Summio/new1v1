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

  const CallWsState({
    this.connected = false,
    this.networkLost = false,
    this.lastMappedEvent,
  });

  CallWsState copyWith({
    bool? connected,
    bool? networkLost,
    CallMappedEvent? lastMappedEvent,
  }) {
    return CallWsState(
      connected: connected ?? this.connected,
      networkLost: networkLost ?? this.networkLost,
      lastMappedEvent: lastMappedEvent ?? this.lastMappedEvent,
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

  void bind() {
    WsService.instance.connect();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();

    _wsSubscription = WsService.instance.events.listen((event) {
      final mapped = CallEventMapper.map(event: event.event, data: event.data);
      state = state.copyWith(lastMappedEvent: mapped);

      if (mapped.shouldSyncBalance) {
        final coins = event.data['coins'] as int?;
        final diamonds = event.data['diamonds'] as int?;
        if (coins != null || diamonds != null) {
          _ref.read(authProvider.notifier).syncBalance(
            coins: coins,
            diamonds: diamonds,
          );
        }
        return;
      }

      if (mapped.shouldShowGift) {
        _ref.read(callGiftControllerProvider(callId).notifier).showGift(
          giftName: event.data['gift_name'] as String? ?? '',
          giftIcon: event.data['gift_icon'] as String? ?? '',
          giftPrice: event.data['gift_price'] as int? ?? 0,
          senderNickname: event.data['sender_nickname'] as String? ?? '用户',
        );
        return;
      }

      if (!mapped.shouldExit) {
        return;
      }

      final eventCallIdRaw = event.data['call_id'];
      final eventCallId = eventCallIdRaw is int
          ? eventCallIdRaw
          : (eventCallIdRaw as num?)?.toInt();
      if (eventCallId != callId) {
        debugPrint('[CallWs] 收到事件 ${event.event} 但 call_id 不匹配: eventCallId=$eventCallId, expected=$callId');
        return;
      }
      debugPrint('[CallWs] 收到通话结束事件，开始结束通话');
      final endReason = _mapEndReasonToString(mapped.endReason);
      _ref.read(callSessionProvider(callId).notifier).beginEnding(
        endReason: endReason,
        notifyEndApi: false,
        endingForBalance: endReason == 'balance_empty',
      );
    });

    _wsConnectionSubscription = WsService.instance.connectionEvents.listen((event) {
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
          _ref.read(callSessionProvider(callId).notifier).beginEnding(
            endReason: 'network_lost',
            notifyEndApi: false,
          );
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
}

final callWsControllerProvider =
    StateNotifierProvider.autoDispose.family<CallWsController, CallWsState, int>(
      (ref, callId) => CallWsController(ref, callId: callId),
    );
