import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallGiftState {
  final bool isShowing;
  final String giftName;
  final String giftIcon;
  final String svgaUrl;
  final int giftPrice;
  final int quantity;
  final int totalPrice;
  final int displaySeq;
  final String scene;
  final int? callId;
  final String senderNickname;

  const CallGiftState({
    this.isShowing = false,
    this.giftName = '',
    this.giftIcon = '',
    this.svgaUrl = '',
    this.giftPrice = 0,
    this.quantity = 1,
    this.totalPrice = 0,
    this.displaySeq = 0,
    this.scene = 'chat',
    this.callId,
    this.senderNickname = '',
  });

  CallGiftState copyWith({
    bool? isShowing,
    String? giftName,
    String? giftIcon,
    String? svgaUrl,
    int? giftPrice,
    int? quantity,
    int? totalPrice,
    int? displaySeq,
    String? scene,
    int? callId,
    String? senderNickname,
  }) {
    return CallGiftState(
      isShowing: isShowing ?? this.isShowing,
      giftName: giftName ?? this.giftName,
      giftIcon: giftIcon ?? this.giftIcon,
      svgaUrl: svgaUrl ?? this.svgaUrl,
      giftPrice: giftPrice ?? this.giftPrice,
      quantity: quantity ?? this.quantity,
      totalPrice: totalPrice ?? this.totalPrice,
      displaySeq: displaySeq ?? this.displaySeq,
      scene: scene ?? this.scene,
      callId: callId ?? this.callId,
      senderNickname: senderNickname ?? this.senderNickname,
    );
  }
}

class CallGiftController extends StateNotifier<CallGiftState> {
  CallGiftController() : super(const CallGiftState());
  static const Duration _normalDisplayDuration = Duration(seconds: 3);

  Timer? _hideTimer;

  void showGift({
    required String giftName,
    required String giftIcon,
    required String svgaUrl,
    required int giftPrice,
    required int quantity,
    required int totalPrice,
    required String scene,
    required int? callId,
    required String senderNickname,
  }) {
    _hideTimer?.cancel();
    state = state.copyWith(
      isShowing: true,
      giftName: giftName,
      giftIcon: giftIcon,
      svgaUrl: svgaUrl,
      giftPrice: giftPrice,
      quantity: quantity,
      totalPrice: totalPrice,
      displaySeq: state.displaySeq + 1,
      scene: scene,
      callId: callId,
      senderNickname: senderNickname,
    );
    // SVGA 场景由播放完成回调关闭；普通礼物保持固定时长自动关闭。
    if (svgaUrl.trim().isEmpty) {
      _hideTimer = Timer(_normalDisplayDuration, hideGift);
    }
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

final callGiftControllerProvider = StateNotifierProvider.autoDispose
    .family<CallGiftController, CallGiftState, int>(
      (ref, callId) => CallGiftController(),
    );
