import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/anchor_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/providers/gift_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/storage/storage.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/svga_once_player.dart';
import '../../services/im_service.dart';
import '../gift/gift_panel.dart';
import 'call_end_reason.dart';
import 'call_overlay_chat_store.dart';
import 'controllers/call_gift_controller.dart';
import 'controllers/call_rtc_controller.dart';
import 'controllers/call_session_controller.dart';
import 'controllers/call_ws_controller.dart';

/// 通话房间页面
/// 页面职责：渲染 + 交互分发 + side-effect 监听
class CallRoomPage extends ConsumerStatefulWidget {
  final int callId;

  /// 通话对端 AppUser ID（用于资料展示）
  final String peerUserId;

  /// 礼物目标 Anchor ID（可选，缺省时尝试按 peerUserId 反查）
  final String? anchorId;
  final String peerName;

  const CallRoomPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    this.anchorId,
    this.peerName = '',
  });

  @override
  ConsumerState<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends ConsumerState<CallRoomPage>
    with WidgetsBindingObserver {
  static const int _callChatHistoryCount = 30;
  static const Duration _keyboardInsetSettleDelay = Duration(milliseconds: 120);
  bool _endingConsuming = false;
  bool _disposed = false;
  bool _isRemoteInMainView = true;
  bool _isChatInputVisible = false;
  bool _isImChatReady = false;
  bool _isImChatAvailable = true;
  bool _isImChatLoading = false;
  double _settledKeyboardInset = 0;
  int? _myAppUserId;
  String? _myChatUserId;
  String? _peerChatUserId;
  String _myDisplayName = '我';
  final IMService _imService = IMService();
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final CallOverlayChatStore _chatStore = CallOverlayChatStore(maxMessages: 20);
  Timer? _keyboardInsetSettleTimer;
  late final DateTime _chatSessionStartedAt;

  void _log(String message) {
    AppLogger.debug('[CALL_FLOW][callId=${widget.callId}] $message');
  }

  @override
  void initState() {
    super.initState();
    _chatSessionStartedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _log(
      'page init, peerUserId=${widget.peerUserId}, '
      'anchorId=${widget.anchorId}, peerName=${widget.peerName}',
    );

    // 使用 Future.microtask 延迟执行，避免 widget build 阶段修改 provider
    Future.microtask(() {
      if (!mounted) return;
      ref.read(callSessionProvider(widget.callId).notifier).markConnecting();
      ref.read(callWsControllerProvider(widget.callId).notifier).bind();

      unawaited(
        ref
            .read(callRtcControllerProvider(widget.callId).notifier)
            .initRtc(
              onCallConnected: () {
                if (!mounted) return;
                ref
                    .read(callSessionProvider(widget.callId).notifier)
                    .markOngoing();
              },
              onRemoteEnd: (endReason) {
                if (!mounted) return;
                ref
                    .read(callSessionProvider(widget.callId).notifier)
                    .beginEnding(endReason: endReason, notifyEndApi: false);
              },
              onLog: _log,
            ),
      );
      unawaited(_initImCallChat());
    });
  }

  @override
  void didChangeMetrics() {
    _scheduleKeyboardInsetSettleUpdate();
  }

  void _scheduleKeyboardInsetSettleUpdate() {
    _keyboardInsetSettleTimer?.cancel();
    _keyboardInsetSettleTimer = Timer(_keyboardInsetSettleDelay, () {
      if (!mounted) {
        return;
      }
      final nextInset = _readKeyboardInset();
      if ((_settledKeyboardInset - nextInset).abs() < 0.5) {
        return;
      }
      setState(() {
        _settledKeyboardInset = nextInset;
      });
    });
  }

  double _readKeyboardInset() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return 0;
    }
    final view = views.first;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  Future<void> _consumeEnding(CallSessionState sessionState) async {
    if (_endingConsuming || sessionState.hasEnded) {
      return;
    }
    _endingConsuming = true;

    final endReason = (sessionState.endReason ?? 'normal').trim();
    _log(
      'session ending, reason=$endReason notifyEndApi=${sessionState.notifyEndApi}',
    );

    try {
      if (sessionState.isEndingForBalance || endReason == 'balance_empty') {
        if (mounted) {
          AppToast.showSnackBar(
            context,
            const SnackBar(content: Text('余额不足，通话即将结束')),
          );
        }
        await Future.delayed(const Duration(seconds: 3));
      } else if (endReason != 'normal') {
        if (mounted) {
          AppToast.showSnackBar(
            context,
            SnackBar(content: Text(callEndReasonText(endReason))),
          );
        }
      }

      final current = ref.read(callSessionProvider(widget.callId));
      if (!current.hasEnded) {
        await _leaveAndExit(
          notifyEndApi: current.notifyEndApi,
          endReason: endReason,
        );
      }
    } finally {
      _endingConsuming = false;
    }
  }

  Future<void> _endCall() async {
    final session = ref.read(callSessionProvider(widget.callId));
    if (session.endingInProgress || session.hasEnded) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认挂断'),
        content: const Text('确定要结束当前通话吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('挂断'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _log('end call canceled by user');
      return;
    }

    _log('end call confirmed');
    ref
        .read(callSessionProvider(widget.callId).notifier)
        .beginEnding(endReason: 'normal', notifyEndApi: true);
  }

  Future<void> _leaveAndExit({
    required bool notifyEndApi,
    required String endReason,
  }) async {
    final sessionNotifier = ref.read(
      callSessionProvider(widget.callId).notifier,
    );
    final current = ref.read(callSessionProvider(widget.callId));
    if (current.hasEnded) {
      return;
    }

    _log('leave and exit start, notifyEndApi=$notifyEndApi reason=$endReason');

    try {
      if (notifyEndApi) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callEnd,
          data: {'call_id': widget.callId},
        );
      }
    } catch (_) {}

    ref.read(callWsControllerProvider(widget.callId).notifier).unbind();
    await ref
        .read(callRtcControllerProvider(widget.callId).notifier)
        .leaveAndRelease(onLog: _log);
    sessionNotifier.markEnded(endReason: endReason);

    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.index);
    }
  }

  int? _resolveGiftTargetAnchorId(AnchorInfo? anchor) {
    final fromRoute = int.tryParse((widget.anchorId ?? '').trim());
    if (fromRoute != null && fromRoute > 0) {
      return fromRoute;
    }
    final fromPeer = int.tryParse(widget.peerUserId.trim());
    if (fromPeer != null && fromPeer > 0) {
      return fromPeer;
    }
    return anchor?.id;
  }

  void _showGiftPanel(AnchorInfo? anchor) {
    final targetAnchorId = _resolveGiftTargetAnchorId(anchor);
    if (targetAnchorId == null || targetAnchorId <= 0) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('目标用户参数异常，暂无法送礼')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftPanel(
        anchorId: targetAnchorId.toString(),
        scene: 'call',
        callId: widget.callId,
        onGiftSent: _handleCallGiftSent,
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  void _handleCallGiftSent(GiftSendResult result) {
    // IM 可用时由 gift_notify 消息落地，避免本地回显与 IM 回执重复两条。
    if (_isImChatReady && _isImChatAvailable) {
      return;
    }
    final myAppUserId = _myAppUserId;
    if (myAppUserId == null || myAppUserId <= 0) {
      return;
    }
    final now = DateTime.now();
    final giftName = (result.giftName ?? '').trim().isEmpty
        ? '礼物'
        : (result.giftName ?? '').trim();
    _chatStore.addIncoming(
      msgId: 'gift_local_${widget.callId}_${now.microsecondsSinceEpoch}',
      text: '[礼物] $giftName x${result.quantity ?? 1}',
      senderId: myAppUserId,
      senderName: _myDisplayName,
      sentAt: now,
      isMe: true,
    );
    if (mounted) {
      setState(() {});
    }
  }

  int? _extractAppUserId(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('chat_')) {
      return int.tryParse(raw.substring('chat_'.length));
    }
    return int.tryParse(raw);
  }

  String _toImUserId(int appUserId) => 'chat_$appUserId';

  Future<UserSigPayload> _requestUserSig({int? peerUserId}) async {
    final response = await DioClient.instance.get(
      ApiEndpoints.imUserSig,
      queryParameters: peerUserId != null
          ? <String, dynamic>{'peer_user_id': peerUserId}
          : null,
    );
    return ResponseParsers.parseUserSigPayload(response.data);
  }

  Future<void> _initImCallChat() async {
    if (_isImChatLoading) {
      return;
    }
    setState(() {
      _isImChatLoading = true;
      _isImChatAvailable = true;
    });

    try {
      await ref.read(appInitProvider.notifier).init();
      final authState = ref.read(authProvider);
      final myAppUserId = authState.userId ?? StorageService.getUserId();
      final peerAppUserId = _extractAppUserId(widget.peerUserId);
      if (myAppUserId == null || myAppUserId <= 0 || peerAppUserId == null) {
        throw Exception('用户信息异常，无法初始化聊天');
      }

      final userSigPayload = await _requestUserSig(peerUserId: peerAppUserId);
      final appInitState = ref.read(appInitProvider);
      final sdkAppId = appInitState.imConfigured
          ? (appInitState.imSdkAppId ?? userSigPayload.sdkAppId)
          : userSigPayload.sdkAppId;

      _myAppUserId = myAppUserId;
      _myChatUserId = _toImUserId(myAppUserId);
      _peerChatUserId = _toImUserId(peerAppUserId);

      final nickname = (authState.username ?? '').trim();
      _myDisplayName = nickname.isEmpty ? '我' : nickname;

      await _imService.ensureReady(
        sdkAppId: sdkAppId,
        userId: _myChatUserId!,
        userSig: userSigPayload.userSig,
      );
      _imService.removeMessageListener(_onImMessageReceived);
      _imService.addMessageListener(_onImMessageReceived);
      await _loadImHistoryForOverlay();

      if (!mounted) return;
      setState(() {
        _isImChatReady = true;
        _isImChatAvailable = true;
      });
    } on ApiException catch (e) {
      _log('init IM chat api error: ${e.message}');
      if (!mounted) return;
      setState(() {
        _isImChatReady = false;
        _isImChatAvailable = false;
      });
      AppToast.showSnackBar(
        context,
        SnackBar(content: Text('聊天暂不可用：${e.message}')),
      );
    } catch (e) {
      _log('init IM chat failed: $e');
      if (!mounted) return;
      setState(() {
        _isImChatReady = false;
        _isImChatAvailable = false;
      });
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('聊天初始化失败，稍后可重试')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImChatLoading = false;
        });
      }
    }
  }

  Future<void> _loadImHistoryForOverlay() async {
    final peerUserId = _peerChatUserId;
    final myAppUserId = _myAppUserId;
    if (peerUserId == null || myAppUserId == null) {
      return;
    }
    final history = await _imService.getC2CHistoryMessage(
      userId: peerUserId,
      count: _callChatHistoryCount,
    );
    if (history.isEmpty) {
      _chatStore.clear();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final items = <CallOverlayMessage>[];
    for (final msg in history.reversed) {
      final giftNotify = _imService.parseGiftNotifyMessage(msg);
      final text = msg.textElem?.text?.trim() ?? '';
      final renderedText = giftNotify?.previewText() ?? text;
      if (renderedText.isEmpty) {
        continue;
      }
      final msgId = (msg.msgID ?? '').trim();
      if (msgId.isEmpty) {
        continue;
      }
      final senderChatUserId = (msg.sender ?? '').trim();
      final senderId = _extractAppUserId(senderChatUserId);
      if (senderId == null) {
        continue;
      }
      final sentAt = msg.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(msg.timestamp! * 1000)
          : DateTime.now();
      if (sentAt.isBefore(_chatSessionStartedAt)) {
        continue;
      }
      final isMe = senderId == myAppUserId;
      items.add(
        CallOverlayMessage(
          msgId: msgId,
          text: renderedText,
          senderId: senderId,
          senderName: isMe ? _myDisplayName : '对方',
          sentAt: sentAt,
          isMe: isMe,
          status: CallOverlayMessageStatus.sent,
        ),
      );
    }

    _chatStore.setInitialMessages(items);
    if (mounted) {
      setState(() {});
    }
  }

  void _onImMessageReceived(dynamic message) {
    final peerChatUserId = _peerChatUserId;
    final myAppUserId = _myAppUserId;
    if (peerChatUserId == null || myAppUserId == null) {
      return;
    }

    final messagePeerUserId = (message?.userID as String?)?.trim() ?? '';
    final senderChatUserId = (message?.sender as String?)?.trim() ?? '';
    final isPeerConversation =
        messagePeerUserId == peerChatUserId ||
        senderChatUserId == peerChatUserId;
    if (!isPeerConversation) {
      return;
    }

    final giftNotify = _imService.parseGiftNotifyMessage(message);
    final text = (message?.textElem?.text as String?)?.trim() ?? '';
    final renderedText = giftNotify?.previewText() ?? text;
    if (renderedText.isEmpty) {
      return;
    }

    final msgId = (message?.msgID as String?)?.trim() ?? '';
    if (msgId.isEmpty) {
      return;
    }

    final senderId = _extractAppUserId(senderChatUserId);
    if (senderId == null) {
      return;
    }

    final timestamp = message?.timestamp as int?;
    final sentAt = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
        : DateTime.now();
    if (sentAt.isBefore(_chatSessionStartedAt)) {
      return;
    }
    final isMe = senderId == myAppUserId;

    _chatStore.addIncoming(
      msgId: msgId,
      text: renderedText,
      senderId: senderId,
      senderName: isMe ? _myDisplayName : '对方',
      sentAt: sentAt,
      isMe: isMe,
    );
    if (giftNotify != null &&
        giftNotify.scene == 'call' &&
        (giftNotify.callId == null || giftNotify.callId == widget.callId)) {
      final currentGiftState = ref.read(
        callGiftControllerProvider(widget.callId),
      );
      if (currentGiftState.isShowing) {
        if (mounted) {
          setState(() {});
        }
        return;
      }
      final quantity = giftNotify.quantity < 1 ? 1 : giftNotify.quantity;
      final totalPrice = giftNotify.totalPrice > 0
          ? giftNotify.totalPrice
          : (giftNotify.unitPrice * quantity);
      ref
          .read(callGiftControllerProvider(widget.callId).notifier)
          .showGift(
            giftName: giftNotify.giftName,
            giftIcon: giftNotify.giftIcon,
            svgaUrl: giftNotify.svgaUrl,
            giftPrice: giftNotify.unitPrice,
            quantity: quantity,
            totalPrice: totalPrice,
            scene: 'call',
            callId: widget.callId,
            senderNickname: giftNotify.senderNickname,
          );
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleChatInput() {
    if (!_isImChatAvailable) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('聊天暂不可用，请稍后再试')),
      );
      return;
    }
    if (!_isImChatReady) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('聊天初始化中，请稍候')),
      );
      return;
    }

    final willShowInput = !_isChatInputVisible;
    setState(() {
      _isChatInputVisible = willShowInput;
      if (!willShowInput) {
        _settledKeyboardInset = 0;
      }
    });
    if (willShowInput) {
      _chatFocusNode.requestFocus();
      _scheduleKeyboardInsetSettleUpdate();
    } else {
      _keyboardInsetSettleTimer?.cancel();
      _chatFocusNode.unfocus();
    }
  }

  void _closeChatInput() {
    if (!_isChatInputVisible) {
      return;
    }
    setState(() {
      _isChatInputVisible = false;
      _settledKeyboardInset = 0;
    });
    _keyboardInsetSettleTimer?.cancel();
    _chatFocusNode.unfocus();
  }

  Future<void> _sendChatMessage() async {
    final peerChatUserId = _peerChatUserId;
    final myAppUserId = _myAppUserId;
    final text = _chatController.text.trim();
    if (text.isEmpty || peerChatUserId == null || myAppUserId == null) {
      return;
    }
    if (!_isImChatReady) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('聊天暂不可用，请稍后再试')),
      );
      return;
    }

    final now = DateTime.now();
    final clientMsgId = '${widget.callId}_${now.microsecondsSinceEpoch}';
    _chatStore.addLocalSending(
      clientMsgId: clientMsgId,
      text: text,
      senderId: myAppUserId,
      senderName: _myDisplayName,
      sentAt: now,
    );
    setState(() {});
    _chatController.clear();

    try {
      final sentMsg = await _imService.sendTextMessage(
        receiver: peerChatUserId,
        text: text,
      );
      final serverMsgId = (sentMsg.msgID ?? '').trim();
      if (serverMsgId.isEmpty) {
        _chatStore.markSendFailed(clientMsgId: clientMsgId);
      } else {
        final sentAt = sentMsg.timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(sentMsg.timestamp! * 1000)
            : DateTime.now();
        _chatStore.markSendSuccess(
          clientMsgId: clientMsgId,
          serverMsgId: serverMsgId,
          sentAt: sentAt,
        );
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _chatStore.markSendFailed(clientMsgId: clientMsgId);
      if (mounted) {
        setState(() {});
        AppToast.showSnackBar(context, SnackBar(content: Text('消息发送失败: $e')));
      }
    }
  }

  Future<void> _retryFailedMessage(CallOverlayMessage message) async {
    if (message.status != CallOverlayMessageStatus.failed) {
      return;
    }
    _chatController.text = message.text;
    _chatController.selection = TextSelection.fromPosition(
      TextPosition(offset: _chatController.text.length),
    );
    await _sendChatMessage();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  bool _shouldBestEffortTerminateOnDispose() {
    final session = ref.read(callSessionProvider(widget.callId));
    final rtcState = ref.read(callRtcControllerProvider(widget.callId));
    return !session.hasEnded && rtcState.isJoined;
  }

  Future<void> _bestEffortTerminateCall() async {
    final session = ref.read(callSessionProvider(widget.callId));
    if (session.hasEnded) {
      return;
    }
    _log('best effort terminate start');
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callEnd,
        data: {'call_id': widget.callId},
      );
    } catch (_) {}
    _log('best effort terminate end');
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _keyboardInsetSettleTimer?.cancel();
    _imService.removeMessageListener(_onImMessageReceived);
    _chatController.dispose();
    _chatFocusNode.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    Future.microtask(() {
      if (!_disposed) {
        ref.read(callWsControllerProvider(widget.callId).notifier).unbind();
        ref
            .read(callRtcControllerProvider(widget.callId).notifier)
            .leaveAndRelease(onLog: _log);
      }
    });
    if (_shouldBestEffortTerminateOnDispose()) {
      unawaited(_bestEffortTerminateCall());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CallSessionState>(callSessionProvider(widget.callId), (
      previous,
      next,
    ) {
      if (next.phase == CallPhase.ending &&
          previous?.phase != CallPhase.ending) {
        unawaited(_consumeEnding(next));
      }
    });

    final rtcState = ref.watch(callRtcControllerProvider(widget.callId));
    final rtcController = ref.watch(
      callRtcControllerProvider(widget.callId).notifier,
    );
    final sessionState = ref.watch(callSessionProvider(widget.callId));
    final giftState = ref.watch(callGiftControllerProvider(widget.callId));
    final tokenNames = ref.watch(tokenNamesProvider);

    final anchorState = ref.watch(anchorListProvider);
    AnchorInfo? found;
    for (final a in anchorState.anchors) {
      if (a.userId.toString() == widget.peerUserId) {
        found = a;
        break;
      }
    }
    final anchor = found;
    final peerName = widget.peerName.trim().isNotEmpty
        ? widget.peerName.trim()
        : (anchor?.username ?? '主播');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_endCall());
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2D1F2F), Color(0xFF1A1A1A)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildRemoteView(
                rtcState: rtcState,
                rtcController: rtcController,
              ),
              if (giftState.isShowing)
                _buildGiftAnimationOverlay(giftState: giftState),
              if (_chatStore.messages.isNotEmpty)
                _buildChatMessageOverlay(context),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isRemoteInMainView = !_isRemoteInMainView;
                    });
                  },
                  child: AnimatedContainer(
                    duration: Duration.zero,
                    width: 90,
                    height: 160,
                    decoration: BoxDecoration(
                      color: rtcState.isCameraOn
                          ? const Color(0xFF2A2A2A)
                          : Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _isRemoteInMainView
                        ? _buildLocalPreview(
                            rtcState: rtcState,
                            rtcController: rtcController,
                          )
                        : _buildRemoteVideo(
                            rtcState: rtcState,
                            rtcController: rtcController,
                            usePlaceholder: false,
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 12,
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _endCall,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatDuration(sessionState.callDuration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (anchor?.callPrice != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${anchor!.callPrice!.toStringAsFixed(0)}${tokenNames.coinName}/min',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                      top: 20,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _ControlButton(
                            icon: rtcState.isMicOn ? Icons.mic : Icons.mic_off,
                            label: rtcState.isMicOn ? '麦克风' : '静音',
                            isActive: !rtcState.isMicOn,
                            onTap: () => unawaited(rtcController.toggleMic()),
                          ),
                          const SizedBox(width: 10),
                          _ControlButton(
                            icon: rtcState.isSpeakerOn
                                ? Icons.volume_up
                                : Icons.volume_off,
                            label: '扬声器',
                            isActive: !rtcState.isSpeakerOn,
                            onTap: () =>
                                unawaited(rtcController.toggleSpeaker()),
                          ),
                          const SizedBox(width: 10),
                          _ControlButton(
                            icon: rtcState.isCameraOn
                                ? Icons.videocam
                                : Icons.videocam_off,
                            label: '摄像头',
                            isActive: !rtcState.isCameraOn,
                            onTap: () =>
                                unawaited(rtcController.toggleCamera()),
                          ),
                          const SizedBox(width: 10),
                          _ControlButton(
                            icon: Icons.card_giftcard,
                            label: '礼物',
                            onTap: () => _showGiftPanel(anchor),
                          ),
                          const SizedBox(width: 10),
                          _ControlButton(
                            icon: Icons.chat_bubble_outline,
                            label: _isImChatLoading ? '聊天中' : '聊天',
                            isActive: _isChatInputVisible,
                            onTap: _toggleChatInput,
                          ),
                          const SizedBox(width: 10),
                          _ControlButton(
                            icon: Icons.flip_camera_ios,
                            label: '翻转',
                            isSpinning: rtcState.isFlipping,
                            onTap: () => unawaited(rtcController.flipCamera()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 116,
                  child: Center(
                    child: GestureDetector(
                      onTap: _endCall,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                          color: AppTheme.errorColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isChatInputVisible)
                _buildChatInputBar(context),
              if (rtcState.isLoading)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteView({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
  }) {
    if (!_isRemoteInMainView) {
      return Positioned.fill(
        child: _buildLocalPreview(
          rtcState: rtcState,
          rtcController: rtcController,
        ),
      );
    }

    return Positioned.fill(
      child: _buildRemoteVideo(
        rtcState: rtcState,
        rtcController: rtcController,
        usePlaceholder: true,
      ),
    );
  }

  Widget _buildRemoteVideo({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
    required bool usePlaceholder,
  }) {
    final engine = rtcController.engine;
    if (rtcState.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            rtcState.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    if (rtcState.remoteUid != null &&
        engine != null &&
        rtcState.channelName != null) {
      final viewKey = usePlaceholder
          ? ValueKey('remote_full_${widget.callId}_${rtcState.remoteUid}')
          : ValueKey('remote_preview_${widget.callId}_${rtcState.remoteUid}');
      return AgoraVideoView(
        key: viewKey,
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(
            uid: rtcState.remoteUid,
            renderMode: RenderModeType.renderModeFit,
            mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
          ),
          connection: RtcConnection(
            channelId: rtcState.channelName,
            localUid: rtcState.localUid,
          ),
          // 优先使用 Flutter Texture 以避免 Android 叠层黑屏。
          useFlutterTexture: true,
        ),
      );
    }

    if (!usePlaceholder) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.person, color: Colors.white30, size: 28),
        ),
      );
    }

    return _buildPlaceholder(rtcState);
  }

  Widget _buildLocalPreview({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
  }) {
    if (!rtcState.isCameraOn) {
      return const Icon(Icons.videocam_off, color: Colors.white30, size: 32);
    }

    if (rtcState.isFlipping) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white70,
          ),
        ),
      );
    }

    final engine = rtcController.engine;
    if (engine == null) {
      return const Center(
        child: Icon(Icons.videocam, color: Colors.white70, size: 30),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
          mirrorMode: rtcState.isFrontCamera
              ? VideoMirrorModeType.videoMirrorModeDisabled
              : VideoMirrorModeType.videoMirrorModeDisabled,
        ),
        useFlutterTexture: true,
      ),
    );
  }

  Widget _buildPlaceholder(CallRtcState rtcState) {
    final statusText = rtcState.hasPeerLeft
        ? '对方已离开通话'
        : (rtcState.isJoined ? '等待对方加入...' : '正在连接视频通话...');

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.2),
                  AppTheme.accentColor.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: const Icon(Icons.person, size: 64, color: Colors.white24),
          ),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          if (rtcState.localUid != null && rtcState.channelName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '频道: ${rtcState.channelName}  UID: ${rtcState.localUid}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGiftAnimationOverlay({required CallGiftState giftState}) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.62),
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: giftState.svgaUrl.isNotEmpty
                      ? SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                          child: SvgaOncePlayer(
                            key: ValueKey(giftState.displaySeq),
                            resUrl: giftState.svgaUrl,
                            fit: BoxFit.contain,
                            onCompleted: () {
                              if (!mounted) return;
                              ref
                                  .read(
                                    callGiftControllerProvider(
                                      widget.callId,
                                    ).notifier,
                                  )
                                  .hideGift();
                            },
                          ),
                        )
                      : giftState.giftIcon.isNotEmpty
                      ? Image.network(
                          giftState.giftIcon,
                          width: 180,
                          height: 180,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.card_giftcard,
                                color: AppTheme.secondaryColor,
                                size: 120,
                              ),
                        )
                      : const Icon(
                          Icons.card_giftcard,
                          color: AppTheme.secondaryColor,
                          size: 120,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessageOverlay(BuildContext context) {
    final visibleMessages = _chatStore.messages.length > 6
        ? _chatStore.messages.sublist(_chatStore.messages.length - 6)
        : _chatStore.messages;

    return _KeyboardAwareChatMessageOverlay(
      messages: visibleMessages,
      isInputVisible: _isChatInputVisible,
      keyboardInset: _settledKeyboardInset,
      onRetry: _retryFailedMessage,
      formatChatTime: _formatChatTime,
      statusSuffix: _statusSuffix,
    );
  }

  Widget _buildChatInputBar(BuildContext context) {
    return _KeyboardAwareChatInputBar(
      controller: _chatController,
      focusNode: _chatFocusNode,
      keyboardInset: _settledKeyboardInset,
      onSend: _sendChatMessage,
      onClose: _closeChatInput,
    );
  }

  String _formatChatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _statusSuffix(CallOverlayMessage message) {
    if (!message.isMe) {
      return '';
    }
    switch (message.status) {
      case CallOverlayMessageStatus.sending:
        return ' 发送中';
      case CallOverlayMessageStatus.failed:
        return ' 失败(点此重发)';
      case CallOverlayMessageStatus.sent:
        return '';
    }
  }
}

class _KeyboardAwareChatMessageOverlay extends StatelessWidget {
  final List<CallOverlayMessage> messages;
  final bool isInputVisible;
  final double keyboardInset;
  final Future<void> Function(CallOverlayMessage message) onRetry;
  final String Function(DateTime time) formatChatTime;
  final String Function(CallOverlayMessage message) statusSuffix;

  const _KeyboardAwareChatMessageOverlay({
    required this.messages,
    required this.isInputVisible,
    required this.keyboardInset,
    required this.onRetry,
    required this.formatChatTime,
    required this.statusSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final paddingBottom = MediaQuery.paddingOf(context).bottom;
    final bottomOffset = paddingBottom + (isInputVisible ? 176 : 188);
    final adjustedBottomOffset = isInputVisible
        ? bottomOffset + keyboardInset
        : bottomOffset;

    return Positioned(
      left: 12,
      right: 12,
      bottom: adjustedBottomOffset,
      child: IgnorePointer(
        ignoring: false,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final message in messages)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      onTap: () => unawaited(onRetry(message)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${message.senderName}: ',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: message.text,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '  ${formatChatTime(message.sentAt)}${statusSuffix(message)}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardAwareChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final double keyboardInset;
  final Future<void> Function() onSend;
  final VoidCallback onClose;

  const _KeyboardAwareChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.keyboardInset,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final paddingBottom = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 12,
      right: 12,
      bottom: paddingBottom + 12 + keyboardInset,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white),
                minLines: 1,
                maxLines: 2,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '输入聊天内容',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => unawaited(onSend()),
              ),
            ),
            IconButton(
              onPressed: () => unawaited(onSend()),
              icon: const Icon(Icons.send, color: Colors.white),
              tooltip: '发送消息',
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: '关闭聊天输入',
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制按钮组件
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isSpinning;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isSpinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Duration.zero,
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.primaryColor.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: isSpinning
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
