import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallGiftState {
  final bool isShowing;
  final String giftName;
  final String giftIcon;
  final int giftPrice;
  final String senderNickname;

  const CallGiftState({
    this.isShowing = false,
    this.giftName = '',
    this.giftIcon = '',
    this.giftPrice = 0,
    this.senderNickname = '',
  });

  CallGiftState copyWith({
    bool? isShowing,
    String? giftName,
    String? giftIcon,
    int? giftPrice,
    String? senderNickname,
  }) {
    return CallGiftState(
      isShowing: isShowing ?? this.isShowing,
      giftName: giftName ?? this.giftName,
      giftIcon: giftIcon ?? this.giftIcon,
      giftPrice: giftPrice ?? this.giftPrice,
      senderNickname: senderNickname ?? this.senderNickname,
    );
  }
}

class CallGiftController extends StateNotifier<CallGiftState> {
  CallGiftController() : super(const CallGiftState());

  Timer? _hideTimer;

  void showGift({
    required String giftName,
    required String giftIcon,
    required int giftPrice,
    required String senderNickname,
  }) {
    _hideTimer?.cancel();
    state = state.copyWith(
      isShowing: true,
      giftName: giftName,
      giftIcon: giftIcon,
      giftPrice: giftPrice,
      senderNickname: senderNickname,
    );
    _hideTimer = Timer(const Duration(seconds: 3), hideGift);
  }

  void hideGift() {
    if (!mounted) return;
    state = state.copyWith(isShowing: false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

final callGiftControllerProvider =
    StateNotifierProvider.autoDispose.family<CallGiftController, CallGiftState, int>(
      (ref, callId) => CallGiftController(),
    );
