import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import '../../app/theme/app_theme.dart';
import '../../services/im_service.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/storage/storage.dart';
import '../../app/providers/auth_provider.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

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

class _ImPageState extends ConsumerState<ImPage> {
  static const String _chatPrefix = 'chat';
  static const double _composerBaseHeight = 68;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final IMService _imService = IMService();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _myUserId;
  String? _peerUserId;
  String? _peerNickname;
  String? _peerAvatarUrl;
  String? _myAvatarUrl;
  final Set<String> _messageIds = <String>{};
  V2TimMessage? _lastHistoryMsg;

  String _normalizeIMUserId(String userId) {
    if (userId.startsWith('chat_')) return userId;
    return '${_chatPrefix}_$userId';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initIM();
  }

  Future<void> _initIM() async {
    setState(() => _isLoading = true);

    try {
      // 1. 拉取统一初始化配置（IM 可降级到 usersig 返回的 sdk_app_id）
      final appInitNotifier = ref.read(appInitProvider.notifier);
      await appInitNotifier.init();
      final appInitState = ref.read(appInitProvider);
      int? sdkAppId = appInitState.imConfigured ? appInitState.imSdkAppId : null;

      // 2. 获取 UserSig（用户态短期凭证仍走独立接口）
      final authState = ref.read(authProvider);
      final myUserId = authState.userId ?? StorageService.getUserId();
      if (myUserId == null) {
        throw Exception('登录状态失效，请重新登录');
      }
      final usersigData = await _requestUserSig();
      final userSig = usersigData.userSig;
      sdkAppId ??= usersigData.sdkAppId;
      if (sdkAppId == null) {
        throw Exception('IM 初始化配置缺失，请联系管理员');
      }

      // 3. 获取当前用户ID
      _myUserId = '${_chatPrefix}_$myUserId';
      _myAvatarUrl = authState.avatar;
      _peerUserId = _normalizeIMUserId(widget.userId);
      _peerNickname = widget.initialPeerNickname;
      _peerAvatarUrl = widget.initialPeerAvatarUrl;
      final myNumId = _extractAppUserId(_myUserId ?? '');
      final peerNumId = _extractAppUserId(_peerUserId ?? '');
      if (_myUserId == _peerUserId || (myNumId != null && peerNumId != null && myNumId == peerNumId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不能和自己聊天')),
          );
          Navigator.of(context).pop();
        }
        return;
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
      await _loadHistoryMessages();
      await _imService.cleanC2CUnread(peerUserId: _peerUserId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('IM 初始化失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 消息接收回调
  void _onMessageReceived(dynamic message) {
    try {
      final msgPeerUserId = message?.userID as String?;
      if (_peerUserId == null || msgPeerUserId == null || msgPeerUserId != _peerUserId) {
        return;
      }

      final text = message?.textElem?.text as String?;
      if (text == null || text.trim().isEmpty) return;

      final sender = message?.sender as String?;
      final isMe = sender != null && sender == _myUserId;
      final timestamp = message?.timestamp as int?;
      final msgId = message?.msgID as String?;
      if (msgId != null && msgId.isNotEmpty) {
        if (_messageIds.contains(msgId)) return;
        _messageIds.add(msgId);
      }

      setState(() {
        _messages.add(_ChatMessage(
          content: text,
          isMe: isMe,
          time: timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
              : DateTime.now(),
        ));
      });
      _scrollToBottom();
      if (_peerUserId != null) {
        _imService.cleanC2CUnread(peerUserId: _peerUserId!);
      }
      debugPrint('IM 页面收到消息');
    } catch (e) {
      debugPrint('IM 消息解析失败: $e');
    }
  }

  Future<void> _loadHistoryMessages() async {
    await _loadMoreHistory(initial: true);
  }

  Future<void> _loadPeerProfile() async {
    if (_peerUserId == null) return;
    try {
      final profiles = await _imService.getUsersProfile(userIds: [_peerUserId!]);
      final V2TimUserFullInfo? profile = profiles[_peerUserId!];
      if (!mounted || profile == null) return;
      final nick = profile.nickName?.trim();
      final face = profile.faceUrl?.trim();
      setState(() {
        _peerNickname = (nick != null && nick.isNotEmpty) ? nick : null;
        _peerAvatarUrl = (face != null && face.isNotEmpty) ? face : null;
      });
    } catch (_) {
      // 昵称/头像拉取失败不影响聊天主流程
    }
  }

  Future<void> _loadPeerProfileFromApp() async {
    final peer = _peerUserId;
    if (peer == null || peer.isEmpty) return;
    final peerNumId = _extractAppUserId(peer);
    if (peerNumId == null) return;

    try {
      final data = await DioClient.instance.apiGet(
        ApiEndpoints.userPublic,
        params: {'user_id': peerNumId},
      );
      final payload = (data['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        final appNick = (payload['nickname'] as String?)?.trim();
        final appAvatar = (payload['avatar'] as String?)?.trim();
        if (appNick != null && appNick.isNotEmpty) {
          _peerNickname = appNick;
        }
        if (appAvatar != null && appAvatar.isNotEmpty) {
          _peerAvatarUrl = appAvatar;
        }
      });
    } catch (_) {
      // App 资料兜底失败不影响聊天主链路
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
      for (final msg in messages.reversed) {
        final msgId = msg.msgID;
        if (msgId != null && msgId.isNotEmpty && _messageIds.contains(msgId)) {
          continue;
        }
        if (msgId != null && msgId.isNotEmpty) {
          _messageIds.add(msgId);
        }
        final text = msg?.textElem?.text as String?;
        if (text == null || text.trim().isEmpty) continue;
        final sender = msg?.sender as String?;
        final isMe = sender != null && sender == _myUserId;
        final timestamp = msg?.timestamp as int?;
        parsed.add(_ChatMessage(
          content: text,
          isMe: isMe,
          time: timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
              : DateTime.now(),
        ));
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
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('IM 历史消息加载异常: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
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
        _messages.add(_ChatMessage(
          content: text,
          isMe: true,
          time: DateTime.now(),
        ));
      });

      _controller.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('消息发送失败: $e')),
        );
      }
    }
  }


  @override
  void dispose() {
    _imService.removeMessageListener(_onMessageReceived);
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final isAtTop = position.pixels <= 60;
    final isUserScrollingToTop = position.userScrollDirection == ScrollDirection.forward;
    if (isAtTop && isUserScrollingToTop) {
      _loadMoreHistory();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  String _peerDisplayName() {
    final nick = _peerNickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    return '';
  }

  int? _extractAppUserId(String imUserId) {
    if (imUserId.startsWith('chat_')) {
      return int.tryParse(imUserId.substring('chat_'.length));
    }
    return int.tryParse(imUserId);
  }

  Future<UserSigPayload> _requestUserSig() async {
    final response = await DioClient.instance.get(ApiEndpoints.imUserSig);
    return ResponseParsers.parseUserSigPayload(response.data);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final safeBottom = media.padding.bottom;
    final composerBottom = (keyboardInset > 0 ? keyboardInset : safeBottom) + 8;
    final listBottomPadding = _composerBaseHeight + composerBottom + 12;
    final maxBubbleWidth = media.size.width * 0.75;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(
          _peerDisplayName(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'block') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('拉黑功能开发中')),
                );
                return;
              }
              if (value == 'report') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('投诉功能开发中')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'block',
                child: Text('拉黑'),
              ),
              PopupMenuItem<String>(
                value: 'report',
                child: Text('投诉'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textHint),
                              SizedBox(height: 12),
                              Text(
                                '暂无消息，开始聊天吧',
                                style: TextStyle(color: AppTheme.textHint),
                              ),
                            ],
                          ),
                        )
                      : RepaintBoundary(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(12, 12, 12, listBottomPadding),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              return _MessageBubble(
                                message: msg,
                                maxBubbleWidth: maxBubbleWidth,
                                avatarUrl: msg.isMe ? _myAvatarUrl : _peerAvatarUrl,
                              );
                            },
                          ),
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: composerBottom),
                    decoration: const BoxDecoration(
                      color: AppTheme.surfaceColor,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.videocam_outlined, color: AppTheme.textSecondary),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('视频通话功能开发中')),
                            );
                          },
                        ),
                        Expanded(
                          child: TextField(
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
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChatMessage {
  final String content;
  final bool isMe;
  final DateTime time;

  _ChatMessage({required this.content, required this.isMe, required this.time});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final double maxBubbleWidth;
  final String? avatarUrl;

  const _MessageBubble({
    required this.message,
    required this.maxBubbleWidth,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isMe) ...[
            _BubbleAvatar(avatarUrl: avatarUrl),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: BoxConstraints(
              maxWidth: maxBubbleWidth,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: message.isMe ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.08),
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
            _BubbleAvatar(avatarUrl: avatarUrl),
          ],
        ],
      ),
    );
  }
}

class _BubbleAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _BubbleAvatar({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl!.trim()) : null,
      child: hasAvatar ? null : const Icon(Icons.person, size: 16, color: AppTheme.primaryColor),
    );
  }
}
