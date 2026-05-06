import 'package:flutter/foundation.dart';

enum CallOverlayMessageStatus { sending, sent, failed }

class CallOverlayMessage {
  final String msgId;
  final String? clientMsgId;
  final String text;
  final int senderId;
  final String senderName;
  final DateTime sentAt;
  final bool isMe;
  final CallOverlayMessageStatus status;

  const CallOverlayMessage({
    required this.msgId,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.sentAt,
    required this.isMe,
    required this.status,
    this.clientMsgId,
  });

  CallOverlayMessage copyWith({
    String? msgId,
    Object? clientMsgId = _NoValue.instance,
    String? text,
    int? senderId,
    String? senderName,
    DateTime? sentAt,
    bool? isMe,
    CallOverlayMessageStatus? status,
  }) {
    return CallOverlayMessage(
      msgId: msgId ?? this.msgId,
      clientMsgId: identical(clientMsgId, _NoValue.instance)
          ? this.clientMsgId
          : clientMsgId as String?,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      sentAt: sentAt ?? this.sentAt,
      isMe: isMe ?? this.isMe,
      status: status ?? this.status,
    );
  }
}

class CallOverlayChatStore {
  CallOverlayChatStore({this.maxMessages = 20});

  final int maxMessages;
  final List<CallOverlayMessage> _messages = <CallOverlayMessage>[];
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<CallOverlayMessage> get messages => List.unmodifiable(_messages);

  void clear() {
    if (_messages.isEmpty) {
      return;
    }
    _messages.clear();
    _markChanged();
  }

  void setInitialMessages(List<CallOverlayMessage> items) {
    _messages
      ..clear()
      ..addAll(items);
    _trimToLimit();
    _markChanged();
  }

  void addLocalSending({
    required String clientMsgId,
    required String text,
    required int senderId,
    required String senderName,
    required DateTime sentAt,
  }) {
    final fallbackMsgId = 'local:$clientMsgId';
    _messages.add(
      CallOverlayMessage(
        msgId: fallbackMsgId,
        clientMsgId: clientMsgId,
        text: text,
        senderId: senderId,
        senderName: senderName,
        sentAt: sentAt,
        isMe: true,
        status: CallOverlayMessageStatus.sending,
      ),
    );
    _trimToLimit();
    _markChanged();
  }

  void markSendSuccess({
    required String clientMsgId,
    required String serverMsgId,
    required DateTime sentAt,
  }) {
    for (var i = 0; i < _messages.length; i++) {
      final item = _messages[i];
      if (item.clientMsgId != clientMsgId) {
        continue;
      }
      _messages[i] = item.copyWith(
        msgId: serverMsgId,
        sentAt: sentAt,
        status: CallOverlayMessageStatus.sent,
      );
      _trimToLimit();
      _markChanged();
      return;
    }
  }

  void markSendFailed({required String clientMsgId}) {
    for (var i = 0; i < _messages.length; i++) {
      final item = _messages[i];
      if (item.clientMsgId != clientMsgId) {
        continue;
      }
      _messages[i] = item.copyWith(status: CallOverlayMessageStatus.failed);
      _markChanged();
      return;
    }
  }

  void addIncoming({
    required String msgId,
    required String text,
    required int senderId,
    required String senderName,
    required DateTime sentAt,
    required bool isMe,
    String? clientMsgId,
  }) {
    final normalizedMsgId = msgId.trim();
    if (normalizedMsgId.isEmpty) {
      return;
    }

    final existed = _messages.any((item) => item.msgId == normalizedMsgId);
    if (existed) {
      return;
    }

    _messages.add(
      CallOverlayMessage(
        msgId: normalizedMsgId,
        clientMsgId: clientMsgId,
        text: text,
        senderId: senderId,
        senderName: senderName,
        sentAt: sentAt,
        isMe: isMe,
        status: CallOverlayMessageStatus.sent,
      ),
    );
    _trimToLimit();
    _markChanged();
  }

  void dispose() {
    revision.dispose();
  }

  void _markChanged() {
    revision.value += 1;
  }

  void _trimToLimit() {
    final limit = maxMessages <= 0 ? 20 : maxMessages;
    if (_messages.length <= limit) {
      return;
    }
    final removeCount = _messages.length - limit;
    _messages.removeRange(0, removeCount);
  }
}

class _NoValue {
  const _NoValue._();

  static const _NoValue instance = _NoValue._();
}
