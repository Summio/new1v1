import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSDKListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// IM 服务封装
/// 腾讯云 IM ( TIM ) Flutter SDK
class IMService {
  static final IMService _instance = IMService._();
  factory IMService() => _instance;
  IMService._();

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 当前登录用户ID
  String? _currentUserId;
  String? get currentUserId => _currentUserId;
  int? _sdkAppId;

  /// 消息监听器列表
  final Set<Function(dynamic)> _messageListeners = <Function(dynamic)>{};
  V2TimAdvancedMsgListener? _advancedMsgListener;

  /// 初始化 IM SDK
  /// [sdkAppId] 腾讯云 IM 应用 ID
  /// [logLevel] 日志级别，默认调试模式
  Future<void> init({
    required int sdkAppId,
    @visibleForTesting LogLevelEnum logLevel = LogLevelEnum.V2TIM_LOG_DEBUG,
  }) async {
    if (_isInitialized) {
      if (_sdkAppId != null && _sdkAppId != sdkAppId) {
        throw Exception('IM SDK 已初始化为不同的 SDKAppID');
      }
      return;
    }

    try {
      final initRes = await TencentImSDKPlugin.v2TIMManager.initSDK(
        sdkAppID: sdkAppId,
        loglevel: logLevel,
        listener: V2TimSDKListener(),
      );
      if (initRes.code != 0) {
        throw Exception('IM SDK 初始化失败: code=${initRes.code}, desc=${initRes.desc}');
      }

      _advancedMsgListener = V2TimAdvancedMsgListener(
        onRecvNewMessage: (message) {
          _onMessageReceived(message);
        },
      );
      await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .addAdvancedMsgListener(listener: _advancedMsgListener!);

      _isInitialized = true;
      _sdkAppId = sdkAppId;
      debugPrint('IM SDK 初始化成功');
    } catch (e) {
      debugPrint('IM SDK 初始化失败: $e');
      rethrow;
    }
  }

  /// 登录 IM
  /// [userId] 用户ID（需与后端生成 usersig 时一致，前缀 chat_）
  /// [userSig] 后端返回的签名
  Future<void> login({
    required String userId,
    required String userSig,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化，请先调用 init()');
    }

    try {
      if (_currentUserId == userId) return;

      final loginRes = await TencentImSDKPlugin.v2TIMManager.login(
        userID: userId,
        userSig: userSig,
      );
      if (loginRes.code != 0) {
        throw Exception('IM 登录失败: code=${loginRes.code}, desc=${loginRes.desc}');
      }
      _currentUserId = userId;
      debugPrint('IM 登录成功');
    } catch (e) {
      debugPrint('IM 登录失败: $e');
      rethrow;
    }
  }

  /// 登出 IM
  Future<void> logout() async {
    if (!_isInitialized || _currentUserId == null) return;

    try {
      final logoutRes = await TencentImSDKPlugin.v2TIMManager.logout();
      if (logoutRes.code != 0) {
        throw Exception('IM 登出失败: code=${logoutRes.code}, desc=${logoutRes.desc}');
      }
      _currentUserId = null;
      debugPrint('IM 登出成功');
    } catch (e) {
      debugPrint('IM 登出失败: $e');
      rethrow;
    }
  }

  /// 发送文本消息
  /// [receiver] 接收者 userID
  /// [text] 消息内容
  Future<V2TimMessage> sendTextMessage({
    required String receiver,
    required String text,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }

    try {
      final createRes = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .createTextMessage(text: text);
      if (createRes.code != 0 || createRes.data?.id == null) {
        throw Exception('创建文本消息失败: code=${createRes.code}, desc=${createRes.desc}');
      }

      final sendRes = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .sendMessage(
            message: createRes.data!.messageInfo,
            receiver: receiver,
            groupID: '',
          );
      if (sendRes.code != 0 || sendRes.data == null) {
        throw Exception('发送消息失败: code=${sendRes.code}, desc=${sendRes.desc}');
      }
      debugPrint('IM 发送成功');
      return sendRes.data!;
    } catch (e) {
      debugPrint('消息发送失败: $e');
      rethrow;
    }
  }

  /// 获取历史消息
  /// [userId] 对方用户ID
  /// [count] 获取数量（默认15）
  Future<List<V2TimMessage>> getC2CHistoryMessage({
    required String userId,
    int count = 15,
    V2TimMessage? lastMsg,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }

    try {
      final historyRes = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .getC2CHistoryMessageList(
            userID: userId,
            count: count,
            lastMsg: lastMsg,
          );
      if (historyRes.code != 0) {
        debugPrint('获取历史消息失败: code=${historyRes.code}, desc=${historyRes.desc}');
        return [];
      }
      return historyRes.data ?? <V2TimMessage>[];
    } catch (e) {
      debugPrint('获取历史消息失败: $e');
      return <V2TimMessage>[];
    }
  }

  Future<void> dumpRecentConversations({int count = 20}) async {
    if (!_isInitialized) return;
    try {
      final convRes = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .getConversationList(nextSeq: '0', count: count);
      if (convRes.code != 0) {
        debugPrint('会话列表获取失败: code=${convRes.code}, desc=${convRes.desc}');
        return;
      }
      final list = convRes.data?.conversationList ?? [];
      if (kDebugMode) {
        debugPrint('会话列表诊断: total=${list.length}');
      }
      for (final conv in list) {
        if (!kDebugMode) break;
        final id = conv.conversationID;
        final userId = conv.userID ?? '';
        final hasLastText = (conv.lastMessage?.textElem?.text?.isNotEmpty ?? false);
        debugPrint('会话: id=$id, userID=$userId, hasLastText=$hasLastText');
      }
    } catch (e) {
      debugPrint('会话列表诊断异常: $e');
    }
  }

  Future<List<V2TimConversation>> getConversationList({int count = 50}) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }
    final res = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .getConversationList(
          nextSeq: '0',
          count: count,
        );
    if (res.code != 0) {
      throw Exception('会话列表获取失败: code=${res.code}, desc=${res.desc}');
    }
    final list = (res.data?.conversationList ?? <V2TimConversation>[])
        .whereType<V2TimConversation>()
        .toList()
      ..sort((a, b) => (b.orderkey ?? 0).compareTo(a.orderkey ?? 0));
    return list;
  }

  Future<void> cleanC2CUnread({
    required String peerUserId,
  }) async {
    if (!_isInitialized) return;
    final conversationID = 'c2c_$peerUserId';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .cleanConversationUnreadMessageCount(
            conversationID: conversationID,
            cleanTimestamp: now,
            cleanSequence: 0,
          );
    } catch (e) {
      debugPrint('清理未读失败: $e');
    }
  }

  Future<void> ensureReady({
    required int sdkAppId,
    required String userId,
    required String userSig,
  }) async {
    if (!_isInitialized) {
      await init(sdkAppId: sdkAppId);
    }
    if (_currentUserId != userId) {
      await login(userId: userId, userSig: userSig);
    }
  }

  Future<Map<String, V2TimUserFullInfo>> getUsersProfile({
    required List<String> userIds,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }
    final unique = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (unique.isEmpty) {
      return <String, V2TimUserFullInfo>{};
    }
    final res = await TencentImSDKPlugin.v2TIMManager.getUsersInfo(
      userIDList: unique,
    );
    if (res.code != 0 || res.data == null) {
      throw Exception('拉取用户资料失败: code=${res.code}, desc=${res.desc}');
    }
    final map = <String, V2TimUserFullInfo>{};
    for (final info in res.data!) {
      final userId = info.userID;
      if (userId == null || userId.isEmpty) continue;
      map[userId] = info;
    }
    return map;
  }

  /// 添加消息监听
  void addMessageListener(Function(dynamic) listener) {
    _messageListeners.add(listener);
  }

  /// 移除消息监听
  void removeMessageListener(Function(dynamic) listener) {
    _messageListeners.remove(listener);
  }

  /// 触发消息接收回调
  void _onMessageReceived(dynamic message) {
    if (kDebugMode) {
      debugPrint('IM 收到新消息');
    }
    for (final listener in _messageListeners) {
      listener(message);
    }
  }
}
