import 'package:flutter/foundation.dart';

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

  /// 消息监听器列表
  final List<Function(dynamic)> _messageListeners = [];

  /// 初始化 IM SDK
  /// [sdkAppId] 腾讯云 IM 应用 ID
  /// [logLevel] 日志级别，默认调试模式
  Future<void> init({
    required int sdkAppId,
    @visibleForTesting int logLevel = 0,
  }) async {
    if (_isInitialized) return;

    try {
      // TODO: 根据实际 SDK API 调用
      // TIMOfflinePushListener config...
      _isInitialized = true;
    } catch (e) {
      debugPrint('IM SDK 初始化失败: $e');
      rethrow;
    }
  }

  /// 登录 IM
  /// [userId] 用户ID（需与后端生成 usersig 时一致，前缀 huanxi_）
  /// [userSig] 后端返回的签名
  Future<void> login({
    required String userId,
    required String userSig,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化，请先调用 init()');
    }

    try {
      // TODO: 根据实际 SDK API 调用
      // await V2TIMManager.getInstance().login(userID: userId, userSig: userSig);
      _currentUserId = userId;
    } catch (e) {
      debugPrint('IM 登录失败: $e');
      rethrow;
    }
  }

  /// 登出 IM
  Future<void> logout() async {
    if (!_isInitialized || _currentUserId == null) return;

    try {
      // TODO: 根据实际 SDK API 调用
      // await V2TIMManager.getInstance().logout();
      _currentUserId = null;
    } catch (e) {
      debugPrint('IM 登出失败: $e');
      rethrow;
    }
  }

  /// 发送文本消息
  /// [receiver] 接收者 userID
  /// [text] 消息内容
  Future<void> sendTextMessage({
    required String receiver,
    required String text,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }

    try {
      // TODO: 根据实际 SDK API 调用
      // final msg = V2TIMMessage();
      // msg.textElem = TextElem(text);
      // await V2TIMManager.getInstance().sendC2CMessage(receiver: receiver, message: msg);
    } catch (e) {
      debugPrint('消息发送失败: $e');
      rethrow;
    }
  }

  /// 获取历史消息
  /// [userId] 对方用户ID
  /// [count] 获取数量（默认15）
  Future<List<dynamic>> getC2CHistoryMessage({
    required String userId,
    int count = 15,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化');
    }

    try {
      // TODO: 根据实际 SDK API 调用
      // final result = await V2TIMManager.getInstance().getC2CHistoryMessageList(
      //   userID: userId,
      //   count: count,
      // );
      // return result ?? [];
      return [];
    } catch (e) {
      debugPrint('获取历史消息失败: $e');
      return [];
    }
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
    for (final listener in _messageListeners) {
      listener(message);
    }
  }
}