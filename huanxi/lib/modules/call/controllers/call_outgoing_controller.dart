import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'call_countdown_controller.dart';

class CallOutgoingState {
  final int leftSeconds;
  final bool isActionInFlight;
  final bool isPageClosing;
  final bool isDialingInFlight;
  final String? errorMessage;

  const CallOutgoingState({
    this.leftSeconds = 30,
    this.isActionInFlight = false,
    this.isPageClosing = false,
    this.isDialingInFlight = false,
    this.errorMessage,
  });

  CallOutgoingState copyWith({
    int? leftSeconds,
    bool? isActionInFlight,
    bool? isPageClosing,
    bool? isDialingInFlight,
    String? errorMessage,
  }) {
    return CallOutgoingState(
      leftSeconds: leftSeconds ?? this.leftSeconds,
      isActionInFlight: isActionInFlight ?? this.isActionInFlight,
      isPageClosing: isPageClosing ?? this.isPageClosing,
      isDialingInFlight: isDialingInFlight ?? this.isDialingInFlight,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CallOutgoingController extends StateNotifier<CallOutgoingState> {
  CallOutgoingController() : super(const CallOutgoingState());

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

  void setDialingInFlight(bool value) {
    state = state.copyWith(isDialingInFlight: value);
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

final callOutgoingControllerProvider =
    StateNotifierProvider.autoDispose<CallOutgoingController, CallOutgoingState>(
      (ref) => CallOutgoingController(),
    );
