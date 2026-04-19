import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_countdown_controller.dart';

class CallIncomingState {
  final int leftSeconds;
  final bool isActionInFlight;
  final bool isPageClosing;
  final String? errorMessage;

  const CallIncomingState({
    this.leftSeconds = 30,
    this.isActionInFlight = false,
    this.isPageClosing = false,
    this.errorMessage,
  });

  CallIncomingState copyWith({
    int? leftSeconds,
    bool? isActionInFlight,
    bool? isPageClosing,
    String? errorMessage,
  }) {
    return CallIncomingState(
      leftSeconds: leftSeconds ?? this.leftSeconds,
      isActionInFlight: isActionInFlight ?? this.isActionInFlight,
      isPageClosing: isPageClosing ?? this.isPageClosing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CallIncomingController extends StateNotifier<CallIncomingState> {
  CallIncomingController() : super(const CallIncomingState());

  final CallCountdownController _countdown = CallCountdownController();

  void initCountdown(
    int leftSeconds, {
    required void Function() onTimeout,
  }) {
    state = state.copyWith(leftSeconds: leftSeconds);
    _countdown.start(
      initialSeconds: leftSeconds,
      onTick: (left) => state = state.copyWith(leftSeconds: left),
      onTimeout: onTimeout,
    );
  }

  void stopCountdown() {
    _countdown.stop();
  }

  void setActionInFlight(bool value) {
    state = state.copyWith(isActionInFlight: value);
  }

  void setPageClosing(bool value) {
    state = state.copyWith(isPageClosing: value);
    if (value) {
      _countdown.stop();
    }
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }
}

final callIncomingControllerProvider =
    StateNotifierProvider.autoDispose<CallIncomingController, CallIncomingState>(
      (ref) => CallIncomingController(),
    );
