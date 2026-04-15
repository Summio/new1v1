import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_theme.dart';
import '../../services/im_service.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../app/providers/auth_provider.dart';

/// IM 聊天页面
/// 发送文字消息（后续接入 WebSocket）
class ImPage extends ConsumerStatefulWidget {
  final String userId;

  const ImPage({super.key, required this.userId});

  @override
  ConsumerState<ImPage> createState() => _ImPageState();
}

class _ImPageState extends ConsumerState<ImPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final IMService _imService = IMService();
  bool _isLoading = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _initIM();
  }

  Future<void> _initIM() async {
    setState(() => _isLoading = true);

    try {
      // 1. 获取 UserSig
      final dio = DioClient.instance;
      final response = await dio.get(ApiEndpoints.imUserSig);
      final usersigData = response['data'];
      final userSig = usersigData['usersig'];

      // 2. 获取当前用户ID
      final authState = ref.read(authProvider);
      _myUserId = 'huanxi_${authState.user?.id}';

      // 3. 初始化并登录 IM（如果未初始化）
      if (!_imService.isInitialized) {
        // SDKAppID 从环境配置获取（ TODO: 可通过后端接口获取）
        const sdkAppId = 0; // TODO: 填入真实 SDKAppID
        await _imService.init(sdkAppId: sdkAppId);
      }
      await _imService.login(userId: _myUserId!, userSig: userSig);

      // 4. 添加消息监听
      _imService.addMessageListener(_onMessageReceived);

      // 5. 加载历史消息
      await _loadHistoryMessages();
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
    // TODO: 根据实际消息格式处理
    // final msg = message as V2TimMessage;
    // setState(() {
    //   _messages.add(_ChatMessage(
    //     content: msg.textElem?.text ?? '',
    //     isMe: false,
    //     time: DateTime.fromMillisecondsSinceEpoch(msg.timestamp * 1000),
    //   ));
    // });
    // _scrollToBottom();
  }

  Future<void> _loadHistoryMessages() async {
    try {
      // TODO: 加载历史消息并转换显示
      // final messages = await _imService.getC2CHistoryMessage(
      //   userId: widget.userId,
      // );
    } catch (e) {
      // 静默失败，使用本地空消息
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      // 发送到 IM
      await _imService.sendTextMessage(
        receiver: widget.userId,
        text: text,
      );

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
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('聊天'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('视频通话功能开发中')),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 聊天区域
                Expanded(
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
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return _MessageBubble(message: msg);
                          },
                        ),
                ),
                // 输入区域
                Container(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: MediaQuery.of(context).padding.bottom + 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppTheme.textSecondary),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('更多功能开发中')),
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
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 发送按钮 - 渐变圆形
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: message.isMe ? AppTheme.primaryGradient : null,
          color: message.isMe ? null : AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isMe ? 16 : 4),
            bottomRight: Radius.circular(message.isMe ? 4 : 16),
          ),
          boxShadow: message.isMe
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
    );
  }
}
