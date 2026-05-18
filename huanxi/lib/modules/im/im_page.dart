import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import '../../app/theme/app_theme.dart';
import '../../app/routes/app_router.dart';
import '../../core/utils/svga_once_player.dart';
import '../../services/im_service.dart';
import '../../services/user_home_service.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/storage.dart';
import '../../core/im/call_trace_message.dart';
import '../../app/providers/auth_provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:huanxi/core/utils/app_toast.dart';
import '../../app/widgets/vip_badge.dart';
import '../gift/gift_panel.dart';
import '../home/main_shell.dart';
import '../home/user_more_actions.dart';

/// IM 聊天页面
/// 发送文字消息（后续接入 WebSocket）
class ImPage extends ConsumerStatefulWidget {
  final String userId;
  final String? initialPeerNickname;
  final String? initialPeerAvatarUrl;

  const ImPage({
    super.key,
    required this.userId,
    this.initialPeerNickname,
    this.initialPeerAvatarUrl,
  });

  @override
  ConsumerState<ImPage> createState() => _ImPageState();
}

class _ImPageState extends ConsumerState<ImPage> with WidgetsBindingObserver {
  static const String _chatPrefix = 'chat';
  static const Duration _giftOverlayDuration = Duration(seconds: 3);
  final _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final IMService _imService = IMService();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _myUserId;
  bool _isCustomerServiceConversation = false;
  String? _peerUserId;
  String? _peerNickname;
  String? _peerAvatarUrl;
  String _peerAvailabilityStatus = 'offline';
  String _peerAvailabilityLabel = '离线';
  int? _peerCertifiedUserId;
  bool _peerIsVip = false;
  String? _myAvatarUrl;
  final Set<String> _messageIds = <String>{};
  V2TimMessage? _lastHistoryMsg;
  bool _isStartingCall = false;
  bool _isSendingText = false;
  bool _blockedByMe = false;
  bool _blockedMe = false;
  bool _interactionBlocked = false;
  GiftNotifyMessage? _fullscreenGift;
  Timer? _fullscreenGiftTimer;
  Timer? _cleanUnreadDebounceTimer;
  StreamSubscription<PresenceEvent>? _presenceSubscription;
  bool _shouldAutoScroll = true;
  bool _stickToBottomForKeyboard = true;
  double _lastKeyboardInset = 0;
  String _normalizeIMUserId(String userId) {
    if (userId.startsWith('chat_')) return userId;
    return '${_chatPrefix}_$userId';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _inputFocusNode.addListener(_onInputFocusChanged);
    _presenceSubscription = MainShell.presenceStream.listen(
      _handlePresenceEvent,
    );
    _initIM();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
    final wasHidden = _lastKeyboardInset <= 0;
    final isVisible = keyboardInset > 0;
    _lastKeyboardInset = keyboardInset;
    if (!isVisible) {
      _stickToBottomForKeyboard = _isNearBottom();
      return;
    }
    if (_inputFocusNode.hasFocus && _stickToBottomForKeyboard) {
      _followKeyboardToBottom();
      if (wasHidden) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_inputFocusNode.hasFocus) return;
          if (_lastKeyboardInset <= 0 || !_stickToBottomForKeyboard) return;
          _followKeyboardToBottom();
        });
      }
    }
  }

  Future<void> _initIM() async {
    setState(() => _isLoading = true);

    try {
      // 1. 拉取统一初始化配置（IM 可降级到 usersig 返回的 sdk_app_id）
      final appInitNotifier = ref.read(appInitProvider.notifier);
      await appInitNotifier.init();
      // 2. 获取 UserSig（用户态短期凭证仍走独立接口）
      final authState = ref.read(authProvider);
      final myUserId = authState.userId ?? StorageService.getUserId();
      if (myUserId == null) {
        throw Exception('登录状态失效，请重新登录');
      }
      final peerNumId = _extractAppUserId(widget.userId);
      final usersigData = await _requestUserSig(peerUserId: peerNumId);
      final userSig = usersigData.userSig;
      final appInitState = ref.read(appInitProvider);
      final sdkAppId = appInitState.imConfigured
          ? (appInitState.imSdkAppId ?? usersigData.sdkAppId)
          : usersigData.sdkAppId;
      final customerServiceUserId =
          appInitState.customerServiceUserId?.trim() ?? '';
      _isCustomerServiceConversation = _matchesCustomerServiceConversation(
        widget.userId,
        customerServiceUserId,
      );

      // 3. 获取当前用户ID
      _myUserId = '${_chatPrefix}_$myUserId';
      _myAvatarUrl = authState.avatar;
      _peerUserId = _normalizeIMUserId(widget.userId);
      if (_isCustomerServiceConversation) {
        _peerNickname = appInitState.customerServiceNickname;
        final customerAvatar = _imService.normalizeMediaUrl(
          appInitState.customerServiceAvatar,
        );
        _peerAvatarUrl = customerAvatar.isNotEmpty ? customerAvatar : null;
      } else {
        _peerNickname = widget.initialPeerNickname;
        _peerAvatarUrl = _imService.normalizeMediaUrl(
          widget.initialPeerAvatarUrl,
        );
      }

      // 4. 初始化并登录 IM（全局会话）
      await _imService.ensureReady(
        sdkAppId: sdkAppId,
        userId: _myUserId!,
        userSig: userSig,
      );

      // 5. 添加消息监听
      _imService.removeMessageListener(_onMessageReceived);
      _imService.addMessageListener(_onMessageReceived);

      // 6. 加载历史消息
      await _loadPeerProfile();
      await _loadPeerProfileFromApp();
      await _refreshBlockStatus();
      await _loadHistoryMessages();
      _scheduleCleanUnread();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 400) {
        final message = AppToast.normalizeMessage(e.message);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(message);
        } else {
          AppToast.showSnackBar(context, SnackBar(content: Text(message)));
        }
        return;
      }
      final message = e is ApiException ? e.message : 'IM 初始化失败: $e';
      AppToast.showSnackBar(context, SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom(force: true);
      }
    }
  }

  // 消息接收回调
  void _onMessageReceived(dynamic message) {
    try {
      final msgPeerUserId = message?.userID as String?;
      if (_peerUserId == null ||
          msgPeerUserId == null ||
          msgPeerUserId != _peerUserId) {
        return;
      }

      final trace = _imService.parseCallTraceMessage(message);
      if (trace != null && !trace.isFinalResult) {
        return;
      }
      final giftNotify = _imService.parseGiftNotifyMessage(message);
      final text = (message?.textElem?.text as String?)?.trim() ?? '';
      if (trace == null && giftNotify == null && text.isEmpty) return;

      final sender = message?.sender as String?;
      final isMe = sender != null && sender == _myUserId;
      final timestamp = message?.timestamp as int?;
      final msgId = message?.msgID as String?;
      if (msgId != null && msgId.isNotEmpty) {
        if (_messageIds.contains(msgId)) return;
        _messageIds.add(msgId);
      }

      final currentUserId = _extractAppUserId(_myUserId ?? '') ?? 0;
      final renderedText =
          giftNotify?.previewText() ??
          (trace != null
              ? trace.toDisplayText(currentUserId: currentUserId)
              : text);

      setState(() {
        _messages.add(
          _ChatMessage(
            msgId: msgId,
            content: renderedText,
            isMe: isMe,
            time: timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
                : DateTime.now(),
            callTrace: trace,
            giftNotify: giftNotify,
          ),
        );
      });
      if (giftNotify != null) {
        _showFullscreenGift(giftNotify);
      }
      _scrollToBottom(animated: true);
      _scheduleCleanUnread();
      debugPrint('IM 页面收到消息');
    } catch (e) {
      debugPrint('IM 消息解析失败: $e');
    }
  }

  Future<void> _loadHistoryMessages() async {
    await _loadMoreHistory(initial: true);
  }

  Future<void> _loadPeerProfile() async {
    if (_isCustomerServiceConversation) return;
    if (_peerUserId == null) return;
    try {
      final profiles = await _imService.getUsersProfile(
        userIds: [_peerUserId!],
      );
      final V2TimUserFullInfo? profile = profiles[_peerUserId!];
      if (!mounted || profile == null) return;
      final nick = profile.nickName?.trim();
      final face = profile.faceUrl?.trim();
      setState(() {
        _peerNickname = (nick != null && nick.isNotEmpty) ? nick : null;
        final imAvatar = _imService.normalizeMediaUrl(face);
        _peerAvatarUrl = imAvatar.isNotEmpty ? imAvatar : null;
      });
    } catch (_) {
      // 昵称/头像拉取失败不影响聊天主流程
    }
  }

  Future<void> _loadPeerProfileFromApp() async {
    if (_isCustomerServiceConversation) return;
    final peer = _peerUserId;
    if (peer == null || peer.isEmpty) return;
    final peerNumId = _extractAppUserId(peer);
    if (peerNumId == null) return;

    try {
      final data = await DioClient.instance.apiGet(
        ApiEndpoints.userPublic,
        params: {'user_id': peerNumId, 'scene': 'chat'},
      );
      final payload =
          (data['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        final appNick = (payload['nickname'] as String?)?.trim();
        final appAvatar = _imService.normalizeMediaUrl(
          (payload['avatar'] as String?)?.trim(),
        );
        final appCertifiedUserId =
            (payload['target_user_id'] as num?)?.toInt() ??
            (payload['certified_user_id'] as num?)?.toInt() ??
            (payload['user_id'] as num?)?.toInt() ??
            (payload['id'] as num?)?.toInt();
        final availabilityStatus = _normalizeAvailabilityStatus(
          payload['availability_status'] as String?,
          payload['is_online'] as bool? ?? false,
        );
        final availabilityLabel = (payload['availability_label'] as String?)
            ?.trim();
        if (appNick != null && appNick.isNotEmpty) {
          _peerNickname = appNick;
        }
        if (appAvatar.isNotEmpty) {
          _peerAvatarUrl = appAvatar;
        }
        _peerAvailabilityStatus = availabilityStatus;
        _peerAvailabilityLabel = availabilityLabel?.isNotEmpty == true
            ? availabilityLabel!
            : _availabilityLabelForStatus(availabilityStatus);
        _peerCertifiedUserId = appCertifiedUserId;
        _peerIsVip = payload['is_vip'] == true;
        _blockedByMe = payload['blocked_by_me'] as bool? ?? _blockedByMe;
        _blockedMe = payload['blocked_me'] as bool? ?? _blockedMe;
        _interactionBlocked =
            payload['interaction_blocked'] as bool? ?? _interactionBlocked;
      });
    } on ApiException catch (e) {
      if (e.code == 400) {
        rethrow;
      }
      // 其它业务错误不影响聊天主链路
    } catch (_) {
      // App 资料兜底失败不影响聊天主链路
    }
  }

  void _handlePresenceEvent(PresenceEvent event) {
    if (!mounted || _isCustomerServiceConversation) return;
    final peerNumId = _extractAppUserId(_peerUserId ?? widget.userId);
    if (peerNumId == null || peerNumId != event.userId) return;
    setState(() {
      _peerAvailabilityStatus = event.availabilityStatus;
      _peerAvailabilityLabel = event.availabilityLabel.trim().isNotEmpty
          ? event.availabilityLabel.trim()
          : _availabilityLabelForStatus(event.availabilityStatus);
    });
  }

  String _normalizeAvailabilityStatus(String? rawStatus, bool isOnline) {
    final status = rawStatus?.trim();
    if (status == 'online' ||
        status == 'busy' ||
        status == 'dnd' ||
        status == 'offline') {
      return status!;
    }
    return isOnline ? 'online' : 'offline';
  }

  String _availabilityLabelForStatus(String status) {
    switch (status) {
      case 'online':
        return '在线';
      case 'busy':
        return '忙碌';
      case 'dnd':
        return '勿扰';
      default:
        return '离线';
    }
  }

  Color _availabilityColor(String status) {
    switch (status) {
      case 'online':
        return AppTheme.onlineGreen;
      case 'busy':
        return const Color(0xFFFF3B30);
      case 'dnd':
        return const Color(0xFFAF52DE);
      default:
        return AppTheme.offlineGray;
    }
  }

  Future<void> _refreshBlockStatus() async {
    if (_isCustomerServiceConversation) return;
    final peerNumId = _extractAppUserId(_peerUserId ?? widget.userId);
    if (peerNumId == null || peerNumId <= 0) return;
    try {
      final status = await UserHomeService.instance.getUserBlockStatus(
        peerNumId,
      );
      if (!mounted) return;
      setState(() {
        _blockedByMe = status.blockedByMe;
        _blockedMe = status.blockedMe;
        _interactionBlocked = status.interactionBlocked;
      });
    } catch (_) {
      // 状态失败不阻塞历史消息查看，实际互动仍由后端拦截
    }
  }

  Future<void> _openMoreActions() async {
    final targetUserId = _extractAppUserId(_peerUserId ?? widget.userId);
    if (targetUserId == null || targetUserId <= 0) return;
    final changed = await showUserMoreActions(
      context: context,
      targetUserId: targetUserId,
      targetName: _peerDisplayName(),
      blockedByMe: _blockedByMe,
      blockedMe: _blockedMe,
    );
    if (changed == true) {
      await _refreshBlockStatus();
    }
  }

  Future<void> _loadMoreHistory({bool initial = false}) async {
    if (_peerUserId == null) return;
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final messages = await _imService.getC2CHistoryMessage(
        userId: _peerUserId!,
        lastMsg: initial ? null : _lastHistoryMsg,
      );
      debugPrint('IM 历史消息条数: ${messages.length}');

      if (!mounted) return;
      if (messages.isEmpty) {
        return;
      }

      final parsed = <_ChatMessage>[];
      final currentUserId = _extractAppUserId(_myUserId ?? '') ?? 0;
      double? beforePixels;
      double? beforeMaxExtent;
      if (!initial && _scrollController.hasClients) {
        beforePixels = _scrollController.position.pixels;
        beforeMaxExtent = _scrollController.position.maxScrollExtent;
      }
      for (final msg in messages.reversed) {
        final msgId = msg.msgID;
        if (msgId != null && msgId.isNotEmpty && _messageIds.contains(msgId)) {
          continue;
        }
        if (msgId != null && msgId.isNotEmpty) {
          _messageIds.add(msgId);
        }
        final trace = _imService.parseCallTraceMessage(msg);
        if (trace != null && !trace.isFinalResult) {
          continue;
        }
        final giftNotify = _imService.parseGiftNotifyMessage(msg);
        final text = msg.textElem?.text?.trim() ?? '';
        if (trace == null && giftNotify == null && text.isEmpty) continue;
        final sender = msg.sender;
        final isMe = sender != null && sender == _myUserId;
        final timestamp = msg.timestamp;
        final renderedText =
            giftNotify?.previewText() ??
            (trace != null
                ? trace.toDisplayText(currentUserId: currentUserId)
                : text);
        parsed.add(
          _ChatMessage(
            msgId: msgId,
            content: renderedText,
            isMe: isMe,
            time: timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
                : DateTime.now(),
            callTrace: trace,
            giftNotify: giftNotify,
          ),
        );
      }
      if (parsed.isEmpty) return;

      setState(() {
        if (initial) {
          _messages
            ..clear()
            ..addAll(parsed);
        } else {
          _messages.insertAll(0, parsed);
        }
      });
      _lastHistoryMsg = messages.last;
      if (initial) {
        _scrollToBottom(force: true);
      } else if (beforePixels != null && beforeMaxExtent != null) {
        final previousPixels = beforePixels;
        final previousMaxExtent = beforeMaxExtent;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          final position = _scrollController.position;
          final newMaxExtent = position.maxScrollExtent;
          final delta = newMaxExtent - previousMaxExtent;
          final target = (previousPixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          _scrollController.jumpTo(target);
        });
      }
    } catch (e) {
      debugPrint('IM 历史消息加载异常: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  void _sendMessage() async {
    if (_isSendingText) return;
    if (_interactionBlocked) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('你们之间已存在黑名单关系，无法聊天')),
      );
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final receiverUserId = _extractAppUserId(_peerUserId ?? widget.userId);
    if (receiverUserId == null || receiverUserId <= 0) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('聊天对象异常')));
      return;
    }

    try {
      _isSendingText = true;
      if (!_isCustomerServiceConversation) {
        final requestId = _newTextChargeRequestId(
          receiverUserId: receiverUserId,
          text: text,
        );
        final charge = await _chargeTextMessageIfNeeded(
          receiverUserId: receiverUserId,
          requestId: requestId,
        );
        ref
            .read(authProvider.notifier)
            .syncBalance(
              coins: charge.coins.toDouble(),
              diamonds: charge.diamonds.toDouble(),
            );
      }

      final sentMsg = await _imService.sendTextMessage(
        receiver: _peerUserId ?? _normalizeIMUserId(widget.userId),
        text: text,
      );
      final sentMsgId = sentMsg.msgID;
      if (sentMsgId != null && sentMsgId.isNotEmpty) {
        _messageIds.add(sentMsgId);
      }

      // 添加到本地列表
      setState(() {
        _messages.add(
          _ChatMessage(
            msgId: sentMsgId,
            content: text,
            isMe: true,
            time: DateTime.now(),
          ),
        );
      });

      _controller.clear();
      _scrollToBottom(animated: true, force: true);
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.message : '消息发送失败: $e';
        AppToast.showSnackBar(context, SnackBar(content: Text(msg)));
      }
    } finally {
      _isSendingText = false;
    }
  }

  String _newTextChargeRequestId({
    required int receiverUserId,
    required String text,
  }) {
    return 'im_text_${DateTime.now().microsecondsSinceEpoch}_${receiverUserId}_${text.hashCode.abs()}';
  }

  Future<IMTextChargePayload> _chargeTextMessageIfNeeded({
    required int receiverUserId,
    required String requestId,
  }) async {
    final data = await DioClient.instance.apiPost(
      ApiEndpoints.imTextCharge,
      data: {'receiver_user_id': receiverUserId, 'request_id': requestId},
    );
    return ResponseParsers.parseIMTextChargePayload(data);
  }

  int? _resolveGiftTargetUserId() {
    if (_peerCertifiedUserId != null && _peerCertifiedUserId! > 0) {
      return _peerCertifiedUserId;
    }
    final peer = _peerUserId ?? widget.userId;
    return _extractAppUserId(peer);
  }

  void _showFullscreenGift(GiftNotifyMessage gift) {
    _fullscreenGiftTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _fullscreenGift = gift;
    });
    if (gift.svgaUrl.trim().isEmpty) {
      _fullscreenGiftTimer = Timer(_giftOverlayDuration, _hideFullscreenGift);
    }
  }

  void _hideFullscreenGift() {
    _fullscreenGiftTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _fullscreenGift = null;
    });
  }

  void _openGiftPanel() {
    if (_interactionBlocked) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('你们之间已存在黑名单关系，无法送礼')),
      );
      return;
    }
    if (_isCustomerServiceConversation) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('客服会话不支持送礼物')),
      );
      return;
    }
    final targetUserId = _resolveGiftTargetUserId();
    if (targetUserId == null || targetUserId <= 0) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('当前聊天对象暂不支持送礼')),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => GiftPanel(
          targetUserId: targetUserId.toString(),
          scene: 'chat',
          onClose: () => Navigator.pop(context),
        ),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceSubscription?.cancel();
    _imService.removeMessageListener(_onMessageReceived);
    _fullscreenGiftTimer?.cancel();
    _cleanUnreadDebounceTimer?.cancel();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _shouldAutoScroll = (position.maxScrollExtent - position.pixels) <= 120;
    if (_inputFocusNode.hasFocus) {
      _stickToBottomForKeyboard = _isNearBottom(threshold: 180);
    }
    final isAtTop = position.pixels <= 60;
    final isUserScrollingToTop =
        position.userScrollDirection == ScrollDirection.forward;
    if (isAtTop && isUserScrollingToTop) {
      _loadMoreHistory();
    }
  }

  void _scheduleCleanUnread() {
    final peer = _peerUserId;
    if (peer == null || peer.isEmpty) return;
    _cleanUnreadDebounceTimer?.cancel();
    _cleanUnreadDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _imService.cleanC2CUnread(peerUserId: peer);
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    _inputFocusNode.unfocus();
  }

  void _onInputFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      _stickToBottomForKeyboard = _isNearBottom(threshold: 220);
      _followKeyboardToBottom();
    }
  }

  bool _isNearBottom({double threshold = 120}) {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <= threshold;
  }

  void _followKeyboardToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 1) return;
      _scrollController.jumpTo(target);
    });
  }

  void _scrollToBottom({bool animated = false, bool force = false}) {
    if (!force && !_shouldAutoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        final target = position.maxScrollExtent;
        final current = position.pixels;
        if ((target - current).abs() < 1) return;
        if (animated) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
          return;
        }
        _scrollController.jumpTo(target);
      }
    });
  }

  String _peerDisplayName() {
    if (_isCustomerServiceConversation) {
      return '在线客服';
    }
    final nick = _peerNickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    return '';
  }

  void _openUserDetailFromChatAvatar({required bool isMe}) {
    if (!isMe && _isCustomerServiceConversation) return;
    final targetUserId = isMe
        ? _extractAppUserId(_myUserId ?? '')
        : _extractAppUserId(_peerUserId ?? widget.userId);
    if (targetUserId == null || targetUserId <= 0) return;
    context.push('${AppRoutes.certifiedUserDetail}?userId=$targetUserId');
  }

  Widget _buildAppBarTitle() {
    if (_isCustomerServiceConversation) {
      return const Text('在线客服', maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                _peerDisplayName(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_peerIsVip) ...[
              const SizedBox(width: 4),
              const VipBadge(dense: true),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '●',
              style: TextStyle(
                color: _availabilityColor(_peerAvailabilityStatus),
                fontSize: 9,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _peerAvailabilityLabel,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _matchesCustomerServiceConversation(
    String rawUserId,
    String customerServiceUserId,
  ) {
    final current = _normalizeComparableUserId(rawUserId);
    final support = _normalizeComparableUserId(customerServiceUserId);
    if (current == null || support == null) return false;
    return current == support;
  }

  String? _normalizeComparableUserId(String rawUserId) {
    final trimmed = rawUserId.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.startsWith('chat_')
        ? trimmed.substring('chat_'.length)
        : trimmed;
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return parsed.toString();
  }

  int? _extractAppUserId(String imUserId) {
    if (imUserId.startsWith('chat_')) {
      return int.tryParse(imUserId.substring('chat_'.length));
    }
    return int.tryParse(imUserId);
  }

  Future<UserSigPayload> _requestUserSig({int? peerUserId}) async {
    final response = await DioClient.instance.get(
      ApiEndpoints.imUserSig,
      queryParameters: peerUserId != null
          ? <String, dynamic>{'peer_user_id': peerUserId}
          : null,
    );
    return ResponseParsers.parseUserSigPayload(response.data);
  }

  Future<void> _startVideoCall() async {
    if (_isCustomerServiceConversation) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('客服会话不支持视频通话')),
      );
      return;
    }
    _dismissKeyboard();
    if (_isStartingCall) return;
    final peerNumId = _extractAppUserId(_peerUserId ?? widget.userId);
    if (peerNumId == null || peerNumId <= 0) {
      if (!mounted) return;
      _dismissKeyboard();
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('目标用户信息异常，无法发起通话')),
      );
      return;
    }
    final targetUserId = _peerCertifiedUserId ?? peerNumId;

    setState(() => _isStartingCall = true);
    try {
      unawaited(
        context
            .push(
              Uri(
                path: AppRoutes.callOutgoing,
                queryParameters: {
                  'peerUserId': peerNumId.toString(),
                  'targetUserId': targetUserId.toString(),
                  'peerName': _peerDisplayName(),
                  'peerAvatar': _peerAvatarUrl ?? '',
                  'peerIsVip': _peerIsVip ? '1' : '0',
                  'callPrice': '0',
                },
              ).toString(),
            )
            .then(_handleCallPageResult)
            .catchError((_) {
              if (!mounted) return;
              _dismissKeyboard();
              AppToast.showSnackBar(
                context,
                const SnackBar(content: Text('通话启动失败，请稍后重试')),
              );
            }),
      );
    } catch (_) {
      if (!mounted) return;
      _dismissKeyboard();
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('通话启动失败，请稍后重试')),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isStartingCall = false);
      });
    }
  }

  void _handleCallPageResult(dynamic result) {
    if (!mounted) return;
    final message = result is String ? result.trim() : '';
    if (message.isEmpty) return;
    AppToast.showSnackBar(context, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final currentUserId = authState.userId ?? StorageService.getUserId() ?? 0;
    final isCurrentUserCertified = authState.isCertifiedUser;
    final size = MediaQuery.sizeOf(context);
    final maxBubbleWidth = size.width * 0.75;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        centerTitle: true,
        titleSpacing: 0,
        title: _buildAppBarTitle(),
        actions: _isCustomerServiceConversation
            ? const []
            : [
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _openMoreActions,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: keyboardInset),
                  child: Column(
                    children: [
                      if (_interactionBlocked)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          color: AppTheme.errorColor.withValues(alpha: 0.08),
                          child: const Text(
                            '你们之间已存在黑名单关系，当前会话只读',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Expanded(
                        child: _messages.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 48,
                                      color: AppTheme.textHint,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      '暂无消息，开始聊天吧',
                                      style: TextStyle(
                                        color: AppTheme.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RepaintBoundary(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    12,
                                  ),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final msg = _messages[index];
                                    return _MessageBubble(
                                      key: ValueKey(msg.stableKey),
                                      message: msg,
                                      maxBubbleWidth: maxBubbleWidth,
                                      currentUserId: currentUserId,
                                      isCurrentUserCertified:
                                          isCurrentUserCertified,
                                      coinName: tokenNames.coinName,
                                      diamondName: tokenNames.diamondName,
                                      avatarUrl: msg.isMe
                                          ? _myAvatarUrl
                                          : _peerAvatarUrl,
                                      onAvatarTap:
                                          !msg.isMe &&
                                              _isCustomerServiceConversation
                                          ? null
                                          : () => _openUserDetailFromChatAvatar(
                                              isMe: msg.isMe,
                                            ),
                                    );
                                  },
                                ),
                              ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.surfaceColor,
                        ),
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Row(
                            children: [
                              if (!_isCustomerServiceConversation)
                                IconButton(
                                  icon: const Icon(
                                    Icons.videocam_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed:
                                      _isStartingCall || _interactionBlocked
                                      ? null
                                      : _startVideoCall,
                                ),
                              if (!_isCustomerServiceConversation)
                                IconButton(
                                  icon: const Icon(
                                    Icons.card_giftcard,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: _interactionBlocked
                                      ? null
                                      : _openGiftPanel,
                                ),
                              Expanded(
                                child: TextField(
                                  focusNode: _inputFocusNode,
                                  controller: _controller,
                                  decoration: InputDecoration(
                                    hintText: '输入消息...',
                                    filled: true,
                                    fillColor: AppTheme.backgroundColor,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                  ),
                                  minLines: 1,
                                  maxLines: 4,
                                  enabled: !_interactionBlocked,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                  ),
                                  onPressed: _interactionBlocked
                                      ? null
                                      : _sendMessage,
                                  disabledColor: AppTheme.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_fullscreenGift != null)
                  _GiftFullscreenOverlay(
                    key: ValueKey(
                      '${_fullscreenGift!.senderId}_${_fullscreenGift!.giftId}_${_fullscreenGift!.timestamp}',
                    ),
                    gift: _fullscreenGift!,
                    coinName: tokenNames.coinName,
                    onClose: _hideFullscreenGift,
                  ),
              ],
            ),
    );
  }
}

class _ChatMessage {
  final String? msgId;
  final String content;
  final bool isMe;
  final DateTime time;
  final CallTraceMessage? callTrace;
  final GiftNotifyMessage? giftNotify;

  _ChatMessage({
    this.msgId,
    required this.content,
    required this.isMe,
    required this.time,
    this.callTrace,
    this.giftNotify,
  });

  bool get isCallTrace => callTrace != null;
  bool get isGiftNotify => giftNotify != null;
  String get stableKey =>
      msgId ??
      'local_${isMe ? 1 : 0}_${time.microsecondsSinceEpoch}_${content.hashCode}';
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final double maxBubbleWidth;
  final int currentUserId;
  final bool isCurrentUserCertified;
  final String coinName;
  final String diamondName;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.maxBubbleWidth,
    required this.currentUserId,
    required this.isCurrentUserCertified,
    required this.coinName,
    required this.diamondName,
    required this.avatarUrl,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isGiftNotify) {
      return _GiftMessageCard(
        message: message,
        maxBubbleWidth: maxBubbleWidth,
        avatarUrl: avatarUrl,
        coinName: coinName,
        onAvatarTap: onAvatarTap,
      );
    }
    if (message.isCallTrace) {
      return _CallTraceCard(
        message: message,
        maxBubbleWidth: maxBubbleWidth,
        currentUserId: currentUserId,
        isCurrentUserCertified: isCurrentUserCertified,
        coinName: coinName,
        diamondName: diamondName,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isMe) ...[
            _BubbleAvatar(avatarUrl: avatarUrl, onTap: onAvatarTap),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: message.isMe
                  ? AppTheme.primaryColor
                  : AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(message.isMe ? 16 : 4),
                bottomRight: Radius.circular(message.isMe ? 4 : 16),
              ),
              boxShadow: null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    color: message.isMe ? Colors.white : AppTheme.textPrimary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: message.isMe ? Colors.white60 : AppTheme.textHint,
                  ),
                ),
              ],
            ),
          ),
          if (message.isMe) ...[
            const SizedBox(width: 8),
            _BubbleAvatar(avatarUrl: avatarUrl, onTap: onAvatarTap),
          ],
        ],
      ),
    );
  }
}

class _GiftMessageCard extends StatelessWidget {
  final _ChatMessage message;
  final double maxBubbleWidth;
  final String? avatarUrl;
  final String coinName;
  final VoidCallback? onAvatarTap;

  const _GiftMessageCard({
    required this.message,
    required this.maxBubbleWidth,
    required this.avatarUrl,
    required this.coinName,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final gift = message.giftNotify!;
    final showIcon = gift.giftIcon.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isMe) ...[
            _BubbleAvatar(avatarUrl: avatarUrl, onTap: onAvatarTap),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: message.isMe
                  ? AppTheme.primaryColor
                  : AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(message.isMe ? 16 : 4),
                bottomRight: Radius.circular(message.isMe ? 4 : 16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon)
                  Image.network(
                    gift.giftIcon,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.card_giftcard, color: Colors.white70),
                  )
                else
                  const Icon(Icons.card_giftcard, color: Colors.white70),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${message.isMe ? '赠送' : '收到'} ${gift.giftName} x${gift.quantity}',
                      style: TextStyle(
                        color: message.isMe
                            ? Colors.white
                            : AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gift.totalPrice > 0
                          ? '总价 ${gift.totalPrice}$coinName'
                          : '单价 ${gift.unitPrice}$coinName',
                      style: TextStyle(
                        color: message.isMe
                            ? Colors.white70
                            : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 10,
                        color: message.isMe
                            ? Colors.white60
                            : AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (message.isMe) ...[
            const SizedBox(width: 8),
            _BubbleAvatar(avatarUrl: avatarUrl, onTap: onAvatarTap),
          ],
        ],
      ),
    );
  }
}

class _CallTraceCard extends StatelessWidget {
  final _ChatMessage message;
  final double maxBubbleWidth;
  final int currentUserId;
  final bool isCurrentUserCertified;
  final String coinName;
  final String diamondName;

  const _CallTraceCard({
    required this.message,
    required this.maxBubbleWidth,
    required this.currentUserId,
    required this.isCurrentUserCertified,
    required this.coinName,
    required this.diamondName,
  });

  @override
  Widget build(BuildContext context) {
    final detail =
        message.callTrace?.detailText(
          currentUserId: currentUserId,
          isCurrentUserCertified: isCurrentUserCertified,
          coinName: coinName,
          diamondName: diamondName,
        ) ??
        '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxBubbleWidth + 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.content,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftFullscreenOverlay extends StatelessWidget {
  final GiftNotifyMessage gift;
  final String coinName;
  final VoidCallback onClose;

  const _GiftFullscreenOverlay({
    super.key,
    required this.gift,
    required this.coinName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasSvga = gift.svgaUrl.trim().isNotEmpty;
    final hasIcon = gift.giftIcon.trim().isNotEmpty;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: hasSvga
                      ? SizedBox.expand(
                          child: SvgaOncePlayer(
                            resUrl: gift.svgaUrl,
                            fit: BoxFit.contain,
                            onCompleted: onClose,
                          ),
                        )
                      : hasIcon
                      ? Image.network(
                          gift.giftIcon,
                          width: 180,
                          height: 180,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.card_giftcard,
                                size: 120,
                                color: Colors.white70,
                              ),
                        )
                      : const Icon(
                          Icons.card_giftcard,
                          size: 120,
                          color: Colors.white70,
                        ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${gift.senderNickname} 送出 ${gift.giftName} x${gift.quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${gift.totalPrice > 0 ? gift.totalPrice : gift.unitPrice}$coinName',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleAvatar extends StatelessWidget {
  final String? avatarUrl;
  final VoidCallback? onTap;

  const _BubbleAvatar({required this.avatarUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl!.trim()) : null,
      child: hasAvatar
          ? null
          : const Icon(Icons.person, size: 16, color: AppTheme.primaryColor),
    );
    if (onTap == null) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: avatar,
    );
  }
}
