import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/websocket_service.dart';

enum CallPhase { idle, connecting, ongoing, ending, ended }

class CallSessionState {
  final int callId;
  final CallPhase phase;
  final String? endReason;
  final Duration callDuration;
  final bool hasEnded;
  final bool endingInProgress;
  final bool isEndingForBalance;
  final bool notifyEndApi;

  const CallSessionState({
    required this.callId,
    this.phase = CallPhase.idle,
    this.endReason,
    this.callDuration = Duration.zero,
    this.hasEnded = false,
    this.endingInProgress = false,
    this.isEndingForBalance = false,
    this.notifyEndApi = false,
  });

  CallSessionState copyWith({
    CallPhase? phase,
    String? endReason,
    Duration? callDuration,
    bool? hasEnded,
    bool? endingInProgress,
    bool? isEndingForBalance,
    bool? notifyEndApi,
  }) {
    return CallSessionState(
      callId: callId,
      phase: phase ?? this.phase,
      endReason: endReason ?? this.endReason,
      callDuration: callDuration ?? this.callDuration,
      hasEnded: hasEnded ?? this.hasEnded,
      endingInProgress: endingInProgress ?? this.endingInProgress,
      isEndingForBalance: isEndingForBalance ?? this.isEndingForBalance,
      notifyEndApi: notifyEndApi ?? this.notifyEndApi,
    );
  }
}

class CallSessionNotifier extends StateNotifier<CallSessionState> {
  CallSessionNotifier({required int callId})
    : super(CallSessionState(callId: callId));

  Timer? _durationTimer;
  Timer? _heartbeatTimer;
  DateTime? _callStartTime;

  void markConnecting() {
    if (state.hasEnded) {
      return;
    }
    state = state.copyWith(phase: CallPhase.connecting);
  }

  void markOngoing() {
    if (state.hasEnded || state.phase == CallPhase.ongoing) {
      return;
    }
    state = state.copyWith(phase: CallPhase.ongoing);
    _startDurationTimer();
    _startHeartbeatTimer();
  }

  bool beginEnding({
    required String endReason,
    required bool notifyEndApi,
    bool endingForBalance = false,
  }) {
    if (state.hasEnded || state.endingInProgress) {
      return false;
    }
    // 立即停止心跳定时器，避免通话结束后继续发送心跳导致 403 错误
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    state = state.copyWith(
      phase: CallPhase.ending,
      endReason: endReason,
      endingInProgress: true,
      isEndingForBalance: endingForBalance,
      notifyEndApi: notifyEndApi,
    );
    return true;
  }

  void markEnded({String? endReason}) {
    _stopRuntimeTimers();
    state = state.copyWith(
      phase: CallPhase.ended,
      hasEnded: true,
      endingInProgress: false,
      endReason: endReason ?? state.endReason,
    );
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callStartTime = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _callStartTime == null) {
        return;
      }
      state = state.copyWith(
        callDuration: DateTime.now().difference(_callStartTime!),
      );
    });
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    unawaited(WsService.instance.sendCallHeartbeat(callId: state.callId));
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || state.hasEnded) {
        return;
      }
      unawaited(WsService.instance.sendCallHeartbeat(callId: state.callId));
    });
  }

  void _stopRuntimeTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  @override
  void dispose() {
    _stopRuntimeTimers();
    super.dispose();
  }
}

final callSessionProvider = StateNotifierProvider.autoDispose
    .family<CallSessionNotifier, CallSessionState, int>(
      (ref, callId) => CallSessionNotifier(callId: callId),
    );
