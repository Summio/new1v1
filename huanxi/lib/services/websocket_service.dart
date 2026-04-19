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

enum WsConnectionState { connected, reconnecting, disconnected, authFailed }

class WsConnectionEvent {
  final WsConnectionState state;
  final String? message;

  const WsConnectionEvent({required this.state, this.message});
}

/// WebSocket 服务
/// 处理与后端的 WebSocket 长连接，用于接收实时推送事件
class WsService {
  WsService._();
  static final WsService _instance = WsService._();
  static WsService get instance => _instance;

  static const Duration _connectReadyTimeout = Duration(seconds: 10);
  static const Duration _authTimeout = Duration(seconds: 10);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  StreamController<WsEvent>? _eventController;
  StreamController<WsConnectionEvent>? _connectionController;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _authTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = false;

  /// 事件流（所有事件）
  Stream<WsEvent> get events {
    _ensureController();
    return _eventController!.stream;
  }

  Stream<WsConnectionEvent> get connectionEvents {
    _ensureConnectionController();
    return _connectionController!.stream;
  }

  /// 是否已连接且认证
  bool get isConnected => _channel != null && _authenticated;

  void _ensureController() {
    _eventController ??= StreamController<WsEvent>.broadcast();
  }

  void _ensureConnectionController() {
    _connectionController ??= StreamController<WsConnectionEvent>.broadcast();
  }

  void _emitConnectionState(WsConnectionState state, {String? message}) {
    _ensureConnectionController();
    _connectionController!.add(
      WsConnectionEvent(state: state, message: message),
    );
  }

  /// 构造 WebSocket URL
  String _buildWsUrl() {
    final base = AppConstants.apiBaseUrl;
    // base 格式: http://host:port/api/v1/ 或 https://host:port/api/v1/
    // WebSocket 端点位于 /api/v1/ws/app，认证通过首帧 JSON 传递 token
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final basePathSegments = uri.pathSegments.where((s) => s.isNotEmpty);
    final wsPathSegments = [...basePathSegments, 'ws', 'app'];
    final wsUri = uri.replace(
      scheme: scheme,
      pathSegments: wsPathSegments,
      query: null,
      fragment: null,
    );
    return wsUri.toString();
  }

  /// 是否已认证
  bool _authenticated = false;

  /// 连接 WebSocket（连接后发送认证首帧）
  Future<void> connect() async {
    if (_isConnecting) return;
    // 关键：存在活动连接（含“认证中”）时不重复建连，避免多页面并发 connect 产生旧连接回调互相覆盖。
    if (_channel != null) return;

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

      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      await channel.ready.timeout(_connectReadyTimeout);
      // 若等待 ready 期间连接已被替换/释放，直接放弃本次尝试，避免污染当前状态。
      if (!identical(_channel, channel)) {
        try {
          channel.sink.close();
        } catch (_) {}
        return;
      }

      // 监听消息（绑定当前 channel，后续旧连接回调会被忽略）
      _channelSubscription?.cancel();
      _channelSubscription = channel.stream.listen(
        (dynamic message) => _onMessage(channel, message),
        onError: (Object error) => _onError(channel, error),
        onDone: () => _onDone(channel),
        cancelOnError: false,
      );

      // 发送认证首帧（后端要求）
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _startAuthTimeout(channel);
    } catch (e) {
      debugPrint('[Ws] 连接失败: $e');
      _clearActiveChannel();
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _startAuthTimeout(WebSocketChannel channel) {
    _authTimer?.cancel();
    _authTimer = Timer(_authTimeout, () {
      if (!identical(_channel, channel) || _authenticated) return;
      debugPrint('[Ws] 认证超时，主动关闭连接并重试');
      try {
        channel.sink.close();
      } catch (_) {}
    });
  }

  void _sendPing() {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (e) {
      debugPrint('[Ws] ping 发送失败: $e');
      // 关键：ping 失败通常代表底层链路已不可用，主动关闭触发 onDone，避免“僵尸连接”长期不重连。
      try {
        _channel?.sink.close();
      } catch (_) {}
    }
  }

  /// 手动设置在线状态（不影响 WebSocket 连接）
  Future<void> sendSetOnlineStatus(bool online) async {
    if (_channel == null || !_authenticated) return;
    try {
      _channel!.sink.add(
        jsonEncode({'type': 'set_online_status', 'online': online}),
      );
    } catch (e) {
      debugPrint('[Ws] set_online_status 发送失败: $e');
    }
  }

  void _onMessage(WebSocketChannel channel, dynamic data) {
    // 旧连接回调（例如并发重连后迟到消息）直接忽略，防止把新连接状态改坏。
    if (!identical(_channel, channel)) return;
    try {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      final type = decoded['type'] as String?;

      if (type == 'auth_success') {
        _authenticated = true;
        _authTimer?.cancel();
        _authTimer = null;
        debugPrint('[Ws] 认证成功, user_id=${decoded['user_id']}');
        _emitConnectionState(WsConnectionState.connected);
        // 认证成功后再启动 ping 定时器；频率小于服务端 heartbeat timeout，避免误判断线
        _pingTimer?.cancel();
        _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
          _sendPing();
        });
        return;
      }

      if (type == 'error') {
        debugPrint('[Ws] 认证失败: ${decoded['code']} ${decoded['msg']}');
        _authTimer?.cancel();
        _authTimer = null;
        _authenticated = false;
        _emitConnectionState(
          WsConnectionState.authFailed,
          message: decoded['msg'] as String?,
        );
        channel.sink.close();
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
          _eventController!.add(
            WsEvent(event: eventName, data: eventData ?? {}),
          );
        }
        return;
      }

      // 忽略其他未知消息类型
    } catch (e) {
      debugPrint('[Ws] 消息解析失败: $e, data=$data');
    }
  }

  void _onError(WebSocketChannel channel, Object error) {
    if (!identical(_channel, channel)) return;
    debugPrint('[Ws] 连接错误: $error');
    _clearActiveChannel();
    _emitConnectionState(WsConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _onDone(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    debugPrint('[Ws] 连接断开');
    _clearActiveChannel();
    if (_shouldReconnect) {
      _emitConnectionState(WsConnectionState.reconnecting);
      _scheduleReconnect();
    } else {
      _emitConnectionState(WsConnectionState.disconnected);
    }
  }

  void _clearActiveChannel() {
    _authenticated = false;
    _channel = null;
    _authTimer?.cancel();
    _authTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _channelSubscription?.cancel();
    _channelSubscription = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_shouldReconnect && _channel == null && !_isConnecting) {
        debugPrint('[Ws] 准备重连...');
        connect();
      }
    });
  }

  /// 断开连接（退出登录时调用）
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _isConnecting = false;
    _authenticated = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _authTimer?.cancel();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _pingTimer = null;
    _authTimer = null;
    _reconnectTimer = null;

    if (_channel != null) {
      final channel = _channel;
      _channel = null;
      try {
        await channel!.sink.close();
      } catch (e) {
        debugPrint('[Ws] 关闭连接失败: $e');
      }
    }
    _emitConnectionState(WsConnectionState.disconnected);

    _eventController?.close();
    _eventController = null;
    _connectionController?.close();
    _connectionController = null;
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}
