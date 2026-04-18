import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants/app_constants.dart';
import '../core/storage/storage.dart';

/// WebSocket 事件类型
class WsEvent {
  final String event;
  final Map<String, dynamic> data;

  const WsEvent({required this.event, required this.data});

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    return WsEvent(
      event: json['event'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// WebSocket 服务
/// 处理与后端的 WebSocket 长连接，用于接收实时推送事件
class WsService {
  WsService._();
  static final WsService _instance = WsService._();
  static WsService get instance => _instance;

  WebSocketChannel? _channel;
  StreamController<WsEvent>? _eventController;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = false;

  /// 事件流（所有事件）
  Stream<WsEvent> get events {
    _ensureController();
    return _eventController!.stream;
  }

  /// 是否已连接且认证
  bool get isConnected => _channel != null && _authenticated;

  void _ensureController() {
    _eventController ??= StreamController<WsEvent>.broadcast();
  }

  /// 构造 WebSocket URL
  String _buildWsUrl() {
    final base = AppConstants.apiBaseUrl;
    // base 格式: http://host:port/api/v1/ 或 https://host:port/api/v1/
    // 后端 /ws/app 端点，认证通过首帧 JSON 传递 token
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final host = uri.host;
    final port = uri.port;
    final portStr = port != 80 && port != 443 ? ':$port' : '';
    return '$scheme://$host$portStr/ws/app';
  }

  /// 是否已认证
  bool _authenticated = false;

  /// 连接 WebSocket（连接后发送认证首帧）
  Future<void> connect() async {
    if (_isConnecting || isConnected) return;

    final token = StorageService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('[Ws] 未登录，跳过 WebSocket 连接');
      return;
    }

    _isConnecting = true;
    _shouldReconnect = true;
    _authenticated = false;

    try {
      final url = _buildWsUrl();
      debugPrint('[Ws] 连接中: $url');

      _channel = WebSocketChannel.connect(Uri.parse(url));

      await _channel!.ready;

      // 发送认证首帧（后端要求）
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      // 监听消息
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnecting = false;
    } catch (e) {
      debugPrint('[Ws] 连接失败: $e');
      _isConnecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _sendPing() {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (e) {
      debugPrint('[Ws] ping 发送失败: $e');
    }
  }

  void _onMessage(dynamic data) {
    try {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      final type = decoded['type'] as String?;

      if (type == 'auth_success') {
        _authenticated = true;
        debugPrint('[Ws] 认证成功, user_id=${decoded['user_id']}');
        // 认证成功后再启动 ping 定时器
        _pingTimer?.cancel();
        _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
          _sendPing();
        });
        return;
      }

      if (type == 'error') {
        debugPrint('[Ws] 认证失败: ${decoded['code']} ${decoded['msg']}');
        _authenticated = false;
        _channel?.sink.close();
        return;
      }

      if (type == 'pong') {
        return; // 忽略 pong 响应
      }

      // 业务事件: {"type": "event", "event": "call_incoming", "data": {...}}
      if (type == 'event') {
        final eventName = decoded['event'] as String?;
        final eventData = decoded['data'] as Map<String, dynamic>?;
        if (eventName != null && eventName.isNotEmpty) {
          debugPrint('[Ws] 收到事件: $eventName');
          _ensureController();
          _eventController!.add(WsEvent(event: eventName, data: eventData ?? {}));
        }
        return;
      }

      // 忽略其他未知消息类型
    } catch (e) {
      debugPrint('[Ws] 消息解析失败: $e, data=$data');
    }
  }

  void _onError(Object error) {
    debugPrint('[Ws] 连接错误: $error');
    _isConnecting = false;
    _authenticated = false;
    _channel = null;
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[Ws] 连接断开');
    _authenticated = false;
    _channel = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_shouldReconnect && !isConnected) {
        debugPrint('[Ws] 准备重连...');
        connect();
      }
    });
  }

  /// 断开连接（退出登录时调用）
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _authenticated = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer = null;

    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        debugPrint('[Ws] 关闭连接失败: $e');
      }
      _channel = null;
    }

    _eventController?.close();
    _eventController = null;
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}
