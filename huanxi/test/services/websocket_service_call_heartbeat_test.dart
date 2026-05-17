import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:huanxi/services/websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = <dynamic>[];

  @override
  void add(data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {
    await for (final item in stream) {
      sent.add(item);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done async {}
}

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel(this.fakeSink);

  final _FakeWebSocketSink fakeSink;

  @override
  Future<void> get ready async {}

  @override
  Stream get stream => const Stream.empty();

  @override
  WebSocketSink get sink => fakeSink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('sendCallHeartbeat should send call_heartbeat payload when authenticated', () async {
    final service = WsService.instance;
    service.debugResetForTest();
    final sink = _FakeWebSocketSink();
    final channel = _FakeWebSocketChannel(sink);
    service.debugInstallChannelForTest(channel, authenticated: true);

    await service.sendCallHeartbeat(callId: 123);
    expect(sink.sent.length, 1);
    final payload = jsonDecode(sink.sent.first as String) as Map<String, dynamic>;
    expect(payload['type'], 'call_heartbeat');
    expect(payload['call_id'], 123);
  });

  test('sendCallHeartbeat should no-op when unauthenticated', () async {
    final service = WsService.instance;
    service.debugResetForTest();
    final sink = _FakeWebSocketSink();
    final channel = _FakeWebSocketChannel(sink);
    service.debugInstallChannelForTest(channel, authenticated: false);

    await service.sendCallHeartbeat(callId: 456);
    expect(sink.sent, isEmpty);
  });

  test('online_status_ack should not be logged as unknown message', () async {
    final service = WsService.instance;
    service.debugResetForTest();
    final sink = _FakeWebSocketSink();
    final channel = _FakeWebSocketChannel(sink);
    service.debugInstallChannelForTest(channel, authenticated: true);

    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
      service.debugResetForTest();
    });

    service.debugHandleMessageForTest(
      channel,
      jsonEncode({'type': 'online_status_ack', 'online': true}),
    );

    expect(
      logs.where((line) => line.contains('收到未知类型消息')),
      isEmpty,
    );
  });
}
