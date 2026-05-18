import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/certified_user_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/providers/gift_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/device/call_keep_alive_bridge.dart';
import '../../core/network/dio_client.dart';
import '../../core/permissions/mandatory_permission_service.dart';
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

  /// 礼物目标用户 ID（可选，缺省时尝试按 peerUserId 反查）
  final String? targetUserId;
  final String peerName;

  const CallRoomPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    this.targetUserId,
    this.peerName = '',
  });

  @override
  ConsumerState<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends ConsumerState<CallRoomPage>
    with WidgetsBindingObserver {
  static const int _callChatHistoryCount = 30;
  static const Duration _connectingWatchdogTimeout = Duration(seconds: 20);
  static const double _chatInputBottomSpacing = 0;
  static const double _chatInputEstimatedHeight = 60;
  static const double _chatOverlayGapAboveInput = 8;

  bool _endingConsuming = false;
  bool _isRemoteInMainView = true;
  bool _isImChatReady = false;
  bool _isImChatAvailable = true;
  bool _isImChatLoading = false;
  int? _myAppUserId;
  String? _myChatUserId;
  String? _peerChatUserId;
  String _myDisplayName = '我';
  CallSessionNotifier? _sessionNotifier;
  CallWsController? _wsController;
  CallRtcController? _rtcController;
  CallSessionState? _lastSessionState;
  CallRtcState? _lastRtcState;
  final IMService _imService = IMService();
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final CallOverlayChatStore _chatStore = CallOverlayChatStore(maxMessages: 20);
  final ValueNotifier<bool> _chatInputVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _callChromeVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _keyboardInset = ValueNotifier<double>(0);
  OverlayEntry? _chatOverlayEntry;
  late final DateTime _chatSessionStartedAt;
  Timer? _connectingWatchdogTimer;

  void _log(String message) {
    AppLogger.debug('[CALL_FLOW][callId=${widget.callId}] $message');
  }

  Future<void> _startCallKeepAlive() async {
    final permissionState = await MandatoryPermissionService.instance
        .ensureReadyForLoggedInUser();
    if (permissionState.requiredGranted) {
      try {
        await CallKeepAliveBridge.startCallMode(callId: widget.callId);
      } catch (e) {
        _log('start call keep alive failed: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCallKeepAlive());
    _chatSessionStartedAt = DateTime.now();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _log(
      'page init, peerUserId=${widget.peerUserId}, '
      'targetUserId=${widget.targetUserId}, peerName=${widget.peerName}',
    );

    // 使用 Future.microtask 延迟执行，避免 widget build 阶段修改 provider
    Future.microtask(() {
      if (!mounted) return;
      _syncKeyboardInsetFromView();
      _ensureChatOverlay();
      _sessionNotifier ??= ref.read(
        callSessionProvider(widget.callId).notifier,
      );
      _sessionNotifier!.markConnecting();
      _startConnectingWatchdog();
      _wsController ??= ref.read(
        callWsControllerProvider(widget.callId).notifier,
      );
      _wsController!.bind();

      _rtcController ??= ref.read(
        callRtcControllerProvider(widget.callId).notifier,
      );
      unawaited(
        _rtcController!.initRtc(
          onCallConnected: () {
            if (!mounted) return;
            _sessionNotifier?.markOngoing();
          },
          onRemoteEnd: (endReason) {
            if (!mounted) return;
            _sessionNotifier?.beginEnding(
              endReason: endReason,
              notifyEndApi: true,
            );
          },
          onLog: _log,
        ),
      );
      unawaited(_initImCallChat());
    });
  }

  void _syncKeyboardInsetFromView() {
    if (!mounted) {
      return;
    }
    final view = View.maybeOf(context);
    if (view == null) {
      return;
    }
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    if ((_keyboardInset.value - inset).abs() < 0.5) {
      return;
    }
    _keyboardInset.value = inset;
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _syncKeyboardInsetFromView();
  }

  Future<void> _consumeEnding(CallSessionState sessionState) async {
    if (_endingConsuming || sessionState.hasEnded) {
      return;
    }
    _endingConsuming = true;

    final currentState = ref.read(callSessionProvider(widget.callId));
    final activeState =
        currentState.isEndingForBalance ||
            (currentState.endReason ?? '').trim() == 'balance_empty'
        ? currentState
        : sessionState;
    final endReason = (activeState.endReason ?? 'normal').trim();
    _log(
      'session ending, reason=$endReason notifyEndApi=${activeState.notifyEndApi}',
    );

    try {
      if (activeState.isEndingForBalance || endReason == 'balance_empty') {
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

    final latestSession = ref.read(callSessionProvider(widget.callId));
    if (latestSession.endingInProgress || latestSession.hasEnded) {
      _log('end call ignored: session already ending/ended');
      return;
    }

    _log('end call confirmed');
    ref
        .read(callSessionProvider(widget.callId).notifier)
        .beginEnding(endReason: 'normal', notifyEndApi: true);
  }

  void _startConnectingWatchdog() {
    _connectingWatchdogTimer?.cancel();
    _connectingWatchdogTimer = Timer(_connectingWatchdogTimeout, () {
      if (!mounted) {
        return;
      }
      final session = ref.read(callSessionProvider(widget.callId));
      final rtcState = ref.read(callRtcControllerProvider(widget.callId));
      if (session.phase != CallPhase.connecting ||
          session.endingInProgress ||
          session.hasEnded ||
          rtcState.isJoined ||
          rtcState.remoteUid != null) {
        return;
      }
      _log('connecting watchdog timeout, force ending to avoid stuck');
      ref
          .read(callSessionProvider(widget.callId).notifier)
          .beginEnding(endReason: 'timeout', notifyEndApi: true);
    });
  }

  void _cancelConnectingWatchdog() {
    _connectingWatchdogTimer?.cancel();
    _connectingWatchdogTimer = null;
  }

  void _dismissTransientOverlays() {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    rootNavigator.popUntil((route) => route is PageRoute<dynamic>);
  }

  void _ensureChatOverlay() {
    if (!mounted) {
      return;
    }
    if (_chatOverlayEntry != null) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    _chatOverlayEntry = OverlayEntry(
      builder: (context) => _CallChatOverlayLayer(
        chatInputVisible: _chatInputVisible,
        callChromeVisible: _callChromeVisible,
        keyboardInset: _keyboardInset,
        revision: _chatStore.revision,
        hasMessages: () => _chatStore.messages.isNotEmpty,
        buildMessageOverlay: _buildChatMessageOverlay,
        controller: _chatController,
        focusNode: _chatFocusNode,
        onSend: _sendChatMessage,
        onClose: _closeChatInput,
        bottomSpacing: _chatInputBottomSpacing,
      ),
    );
    overlay.insert(_chatOverlayEntry!);
  }

  void _removeChatOverlay() {
    _chatOverlayEntry?.remove();
    _chatOverlayEntry = null;
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
    await MandatoryPermissionService.instance.ensureReadyForLoggedInUser();
    sessionNotifier.markEnded(endReason: endReason);

    if (!mounted) {
      return;
    }
    _dismissTransientOverlays();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.index);
    }
  }

  int? _resolveGiftTargetUserId(CertifiedUserInfo? certifiedUser) {
    final fromRoute = int.tryParse((widget.targetUserId ?? '').trim());
    if (fromRoute != null && fromRoute > 0) {
      return fromRoute;
    }
    final fromPeer = int.tryParse(widget.peerUserId.trim());
    if (fromPeer != null && fromPeer > 0) {
      return fromPeer;
    }
    return certifiedUser?.id;
  }

  void _showGiftPanel(CertifiedUserInfo? certifiedUser) {
    final targetUserId = _resolveGiftTargetUserId(certifiedUser);
    if (targetUserId == null || targetUserId <= 0) {
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
        targetUserId: targetUserId.toString(),
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
  }

  CertifiedUserInfo? _findCertifiedUserForPeer() {
    final certifiedUserState = ref.read(certifiedUserListProvider);
    for (final certifiedUser in certifiedUserState.certifiedUsers) {
      if (certifiedUser.userId.toString() == widget.peerUserId) {
        return certifiedUser;
      }
    }
    return null;
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

    final willShowInput = !_chatInputVisible.value;
    _chatInputVisible.value = willShowInput;
    if (willShowInput) {
      _chatFocusNode.requestFocus();
    } else {
      _chatFocusNode.unfocus();
    }
  }

  void _closeChatInput() {
    if (!_chatInputVisible.value) {
      return;
    }
    _chatInputVisible.value = false;
    _chatFocusNode.unfocus();
  }

  void _toggleCallChrome() {
    if (_chatInputVisible.value) {
      _closeChatInput();
      return;
    }
    final visible = _callChromeVisible.value;
    _callChromeVisible.value = !visible;
  }

  Future<void> _openRechargePage() async {
    if (_chatInputVisible.value) {
      _closeChatInput();
    }
    await context.push(AppRoutes.recharge);
    if (!mounted) {
      return;
    }
    await ref.read(authProvider.notifier).refreshBalance();
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
    } catch (e) {
      _chatStore.markSendFailed(clientMsgId: clientMsgId);
      if (mounted) {
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
    final session = _lastSessionState;
    final rtcState = _lastRtcState;
    if (session == null || rtcState == null) {
      return false;
    }
    return !session.hasEnded && rtcState.isJoined;
  }

  Future<void> _bestEffortTerminateCall() async {
    final session = _lastSessionState;
    if (session?.hasEnded ?? true) {
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
    _removeChatOverlay();
    _cancelConnectingWatchdog();
    _imService.removeMessageListener(_onImMessageReceived);
    _chatController.dispose();
    _chatFocusNode.dispose();
    _chatInputVisible.dispose();
    _callChromeVisible.dispose();
    _keyboardInset.dispose();
    _chatStore.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    _wsController?.unbind();
    final rtcController = _rtcController;
    if (rtcController != null) {
      unawaited(rtcController.leaveAndRelease(onLog: _log, updateState: false));
    }
    if (_shouldBestEffortTerminateOnDispose()) {
      unawaited(_bestEffortTerminateCall());
    }
    unawaited(MandatoryPermissionService.instance.ensureReadyForLoggedInUser());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(callWsControllerProvider(widget.callId));
    ref.listen<CallWsState>(callWsControllerProvider(widget.callId), (
      previous,
      next,
    ) {
      if ((previous?.balanceLowNoticeSeq ?? 0) == next.balanceLowNoticeSeq) {
        return;
      }
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('余额不足下一分钟通话费用，请及时充值')),
      );
    });
    final sessionState = ref.watch(callSessionProvider(widget.callId));
    _lastSessionState = sessionState;
    ref.listen<CallSessionState>(callSessionProvider(widget.callId), (
      previous,
      next,
    ) {
      _lastSessionState = next;
      if (next.phase == CallPhase.connecting &&
          previous?.phase != CallPhase.connecting) {
        _startConnectingWatchdog();
      } else if (next.phase != CallPhase.connecting &&
          previous?.phase == CallPhase.connecting) {
        _cancelConnectingWatchdog();
      }
      if (next.phase == CallPhase.ending &&
          previous?.phase != CallPhase.ending) {
        unawaited(_consumeEnding(next));
      }
    });

    final rtcState = ref.watch(callRtcControllerProvider(widget.callId));
    _lastRtcState = rtcState;
    final rtcController = ref.watch(
      callRtcControllerProvider(widget.callId).notifier,
    );
    _rtcController ??= rtcController;

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
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleCallChrome,
                  child: RepaintBoundary(
                    child: _buildRemoteView(
                      rtcState: rtcState,
                      rtcController: rtcController,
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (context, ref, child) {
                  final giftState = ref.watch(
                    callGiftControllerProvider(widget.callId),
                  );
                  if (!giftState.isShowing) {
                    return const SizedBox.shrink();
                  }
                  return _buildGiftAnimationOverlay(giftState: giftState);
                },
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isRemoteInMainView = !_isRemoteInMainView;
                    });
                  },
                  child: Container(
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
              _CallTopBar(
                callId: widget.callId,
                peerUserId: widget.peerUserId,
                routePeerName: widget.peerName,
                formatDuration: _formatDuration,
                callChromeVisible: _callChromeVisible,
              ),
              _CallBottomControls(
                rtcState: rtcState,
                rtcController: rtcController,
                isChatInputVisible: _chatInputVisible,
                callChromeVisible: _callChromeVisible,
                isImChatLoading: _isImChatLoading,
                onToggleChat: _toggleChatInput,
                onShowGift: () => _showGiftPanel(_findCertifiedUserForPeer()),
                onRecharge: () => unawaited(_openRechargePage()),
              ),
              _CallHangupButton(
                isChatInputVisible: _chatInputVisible,
                callChromeVisible: _callChromeVisible,
                onTap: _endCall,
              ),
              if (rtcState.isLoading)
                IgnorePointer(
                  ignoring: true,
                  child: Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
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
      return _buildLocalPreview(
        rtcState: rtcState,
        rtcController: rtcController,
      );
    }

    return _buildRemoteVideo(
      rtcState: rtcState,
      rtcController: rtcController,
      usePlaceholder: true,
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

  Widget _buildChatMessageOverlay() {
    final allMessages = _chatStore.messages;
    final startIndex = allMessages.length > 6 ? allMessages.length - 6 : 0;

    return _KeyboardAwareChatMessageOverlay(
      messages: allMessages,
      startIndex: startIndex,
      chatInputVisible: _chatInputVisible,
      keyboardInset: _keyboardInset,
      bottomSpacing: _chatInputBottomSpacing,
      inputEstimatedHeight: _chatInputEstimatedHeight,
      overlayGapAboveInput: _chatOverlayGapAboveInput,
      onRetry: _retryFailedMessage,
      formatChatTime: _formatChatTime,
      statusSuffix: _statusSuffix,
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
  final int startIndex;
  final ValueNotifier<bool> chatInputVisible;
  final ValueNotifier<double> keyboardInset;
  final double bottomSpacing;
  final double inputEstimatedHeight;
  final double overlayGapAboveInput;
  final Future<void> Function(CallOverlayMessage message) onRetry;
  final String Function(DateTime time) formatChatTime;
  final String Function(CallOverlayMessage message) statusSuffix;

  const _KeyboardAwareChatMessageOverlay({
    required this.messages,
    required this.startIndex,
    required this.chatInputVisible,
    required this.keyboardInset,
    required this.bottomSpacing,
    required this.inputEstimatedHeight,
    required this.overlayGapAboveInput,
    required this.onRetry,
    required this.formatChatTime,
    required this.statusSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: chatInputVisible,
      builder: (context, isVisible, _) {
        return ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, keyboardBottom, _) {
            final safeBottom = MediaQuery.paddingOf(context).bottom;
            final bottomOffset = isVisible
                ? safeBottom +
                      (keyboardBottom > 0 ? keyboardBottom : bottomSpacing) +
                      inputEstimatedHeight +
                      overlayGapAboveInput
                : safeBottom + 188;
            return Positioned(
              left: 12,
              right: 12,
              bottom: bottomOffset,
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
                        for (int i = startIndex; i < messages.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: GestureDetector(
                              onTap: () => unawaited(onRetry(messages[i])),
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
                                        text: '${messages[i].senderName}: ',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(
                                        text: messages[i].text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            '  ${formatChatTime(messages[i].sentAt)}${statusSuffix(messages[i])}',
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
          },
        );
      },
    );
  }
}

class _KeyboardAwareChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final VoidCallback onClose;

  const _KeyboardAwareChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final inputTheme = Theme.of(context).copyWith(
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF1F2937),
        selectionColor: Color(0x332563EB),
        selectionHandleColor: Color(0xFF2563EB),
      ),
    );
    return Theme(
      data: inputTheme,
      child: Material(
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(color: Colors.white),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: const Color(0xFF1F2937),
                  cursorOpacityAnimates: true,
                  minLines: 1,
                  maxLines: 2,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: '输入聊天内容',
                    hintStyle: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => unawaited(onSend()),
                ),
              ),
              IconButton(
                onPressed: () => unawaited(onSend()),
                icon: const Icon(Icons.send, color: Color(0xFF111827)),
                tooltip: '发送消息',
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                tooltip: '关闭聊天输入',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallTopBar extends ConsumerWidget {
  final int callId;
  final String peerUserId;
  final String routePeerName;
  final String Function(Duration) formatDuration;
  final ValueNotifier<bool> callChromeVisible;

  const _CallTopBar({
    required this.callId,
    required this.peerUserId,
    required this.routePeerName,
    required this.formatDuration,
    required this.callChromeVisible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certifiedUserState = ref.watch(certifiedUserListProvider);
    CertifiedUserInfo? certifiedUser;
    for (final item in certifiedUserState.certifiedUsers) {
      if (item.userId.toString() == peerUserId) {
        certifiedUser = item;
        break;
      }
    }
    final peerName = routePeerName.trim().isNotEmpty
        ? routePeerName.trim()
        : (certifiedUser?.username ?? '认证用户');

    return ValueListenableBuilder<bool>(
      valueListenable: callChromeVisible,
      builder: (context, visible, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: visible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !visible,
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
                          _CallDurationText(
                            callId: callId,
                            formatDuration: formatDuration,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallBottomControls extends StatelessWidget {
  final CallRtcState rtcState;
  final CallRtcController rtcController;
  final ValueNotifier<bool> isChatInputVisible;
  final ValueNotifier<bool> callChromeVisible;
  final bool isImChatLoading;
  final VoidCallback onToggleChat;
  final VoidCallback onShowGift;
  final VoidCallback onRecharge;

  const _CallBottomControls({
    required this.rtcState,
    required this.rtcController,
    required this.isChatInputVisible,
    required this.callChromeVisible,
    required this.isImChatLoading,
    required this.onToggleChat,
    required this.onShowGift,
    required this.onRecharge,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return ValueListenableBuilder<bool>(
      valueListenable: callChromeVisible,
      builder: (context, isChromeVisible, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: isChatInputVisible,
          builder: (context, isInputVisible, _) {
            final controlsVisible = isChromeVisible && !isInputVisible;
            return Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: controlsVisible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: safeBottom + 24,
                      top: 20,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final rawButtonWidth = (constraints.maxWidth - 36) / 4;
                        final buttonWidth = rawButtonWidth < 50
                            ? 50.0
                            : rawButtonWidth > 76
                            ? 76.0
                            : rawButtonWidth;
                        return Align(
                          alignment: Alignment.center,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            runAlignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 14,
                            children: [
                              _ControlButton(
                                width: buttonWidth,
                                icon: rtcState.isMicOn
                                    ? Icons.mic
                                    : Icons.mic_off,
                                label: rtcState.isMicOn ? '麦克风' : '静音',
                                isActive: !rtcState.isMicOn,
                                onTap: () =>
                                    unawaited(rtcController.toggleMic()),
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: rtcState.isSpeakerOn
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                label: '扬声器',
                                isActive: !rtcState.isSpeakerOn,
                                onTap: () =>
                                    unawaited(rtcController.toggleSpeaker()),
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: rtcState.isCameraOn
                                    ? Icons.videocam
                                    : Icons.videocam_off,
                                label: '摄像头',
                                isActive: !rtcState.isCameraOn,
                                onTap: () =>
                                    unawaited(rtcController.toggleCamera()),
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: Icons.flip_camera_ios,
                                label: '翻转',
                                isSpinning: rtcState.isFlipping,
                                onTap: () =>
                                    unawaited(rtcController.flipCamera()),
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: Icons.account_balance_wallet_outlined,
                                label: '充值',
                                onTap: onRecharge,
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: Icons.chat_bubble_outline,
                                label: '文字',
                                isActive: isInputVisible,
                                onTap: onToggleChat,
                              ),
                              _ControlButton(
                                width: buttonWidth,
                                icon: Icons.card_giftcard,
                                label: '礼物',
                                onTap: onShowGift,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CallHangupButton extends StatelessWidget {
  final ValueNotifier<bool> isChatInputVisible;
  final ValueNotifier<bool> callChromeVisible;
  final VoidCallback onTap;

  const _CallHangupButton({
    required this.isChatInputVisible,
    required this.callChromeVisible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return ValueListenableBuilder<bool>(
      valueListenable: callChromeVisible,
      builder: (context, isChromeVisible, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: isChatInputVisible,
          builder: (context, isInputVisible, _) {
            final visible = isChromeVisible && !isInputVisible;
            return Positioned(
              left: 0,
              right: 0,
              bottom: safeBottom + 206,
              child: Opacity(
                opacity: visible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: Center(
                    child: GestureDetector(
                      onTap: onTap,
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
              ),
            );
          },
        );
      },
    );
  }
}

class _CallChatOverlayLayer extends StatelessWidget {
  final ValueNotifier<bool> chatInputVisible;
  final ValueNotifier<bool> callChromeVisible;
  final ValueNotifier<double> keyboardInset;
  final ValueNotifier<int> revision;
  final bool Function() hasMessages;
  final Widget Function() buildMessageOverlay;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final VoidCallback onClose;
  final double bottomSpacing;

  const _CallChatOverlayLayer({
    required this.chatInputVisible,
    required this.callChromeVisible,
    required this.keyboardInset,
    required this.revision,
    required this.hasMessages,
    required this.buildMessageOverlay,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.bottomSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: callChromeVisible,
      builder: (context, isChromeVisible, _) {
        if (!isChromeVisible) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (context, _, child) {
                  if (!hasMessages()) {
                    return const SizedBox.shrink();
                  }
                  return buildMessageOverlay();
                },
              ),
              _CallChatInputOverlay(
                chatInputVisible: chatInputVisible,
                keyboardInset: keyboardInset,
                controller: controller,
                focusNode: focusNode,
                onSend: onSend,
                onClose: onClose,
                bottomSpacing: bottomSpacing,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CallChatInputOverlay extends StatelessWidget {
  final ValueNotifier<bool> chatInputVisible;
  final ValueNotifier<double> keyboardInset;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final VoidCallback onClose;
  final double bottomSpacing;

  const _CallChatInputOverlay({
    required this.chatInputVisible,
    required this.keyboardInset,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.bottomSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: chatInputVisible,
      builder: (context, isInputVisible, _) {
        return ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, keyboardBottom, _) {
            final paddingBottom = MediaQuery.paddingOf(context).bottom;
            final bottomInset = keyboardBottom > 0
                ? keyboardBottom
                : (paddingBottom + bottomSpacing);
            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !isInputVisible,
                child: Opacity(
                  opacity: isInputVisible ? 1 : 0,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: _KeyboardAwareChatInputBar(
                      controller: controller,
                      focusNode: focusNode,
                      onSend: onSend,
                      onClose: onClose,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CallDurationText extends ConsumerWidget {
  final int callId;
  final String Function(Duration) formatDuration;
  final TextStyle style;

  const _CallDurationText({
    required this.callId,
    required this.formatDuration,
    required this.style,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callDuration = ref.watch(
      callSessionProvider(callId).select((state) => state.callDuration),
    );
    return Text(formatDuration(callDuration), style: style);
  }
}

/// 控制按钮组件
class _ControlButton extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isSpinning;

  const _ControlButton({
    this.width = 64,
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
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
