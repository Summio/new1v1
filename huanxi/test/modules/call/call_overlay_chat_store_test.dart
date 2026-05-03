import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/call/call_overlay_chat_store.dart';

void main() {
  group('CallOverlayChatStore', () {
    test('should update local sending message to sent with server msg id', () {
      final store = CallOverlayChatStore(maxMessages: 20);
      store.addLocalSending(
        clientMsgId: 'local-1',
        text: 'hello',
        senderId: 1,
        senderName: '我',
        sentAt: DateTime(2026, 1, 1, 12, 0, 0),
      );

      store.markSendSuccess(
        clientMsgId: 'local-1',
        serverMsgId: 'srv-1',
        sentAt: DateTime(2026, 1, 1, 12, 0, 1),
      );

      expect(store.messages, hasLength(1));
      expect(store.messages.first.status, CallOverlayMessageStatus.sent);
      expect(store.messages.first.msgId, 'srv-1');
    });

    test('should mark local message failed when send failed', () {
      final store = CallOverlayChatStore(maxMessages: 20);
      store.addLocalSending(
        clientMsgId: 'local-2',
        text: 'fail me',
        senderId: 1,
        senderName: '我',
        sentAt: DateTime(2026, 1, 1, 12, 0, 0),
      );

      store.markSendFailed(clientMsgId: 'local-2');

      expect(store.messages, hasLength(1));
      expect(store.messages.first.status, CallOverlayMessageStatus.failed);
    });

    test('should dedupe incoming server message by msg id', () {
      final store = CallOverlayChatStore(maxMessages: 20);
      final sentAt = DateTime(2026, 1, 1, 12, 0, 0);

      store.addIncoming(
        msgId: 'srv-dup-1',
        text: 'same',
        senderId: 2,
        senderName: '对方',
        sentAt: sentAt,
        isMe: false,
      );

      store.addIncoming(
        msgId: 'srv-dup-1',
        text: 'same',
        senderId: 2,
        senderName: '对方',
        sentAt: sentAt,
        isMe: false,
      );

      expect(store.messages, hasLength(1));
    });

    test('should trim to maxMessages and keep newest ones', () {
      final store = CallOverlayChatStore(maxMessages: 3);
      for (var i = 0; i < 5; i++) {
        store.addIncoming(
          msgId: 'srv-$i',
          text: 'msg-$i',
          senderId: 2,
          senderName: '对方',
          sentAt: DateTime(2026, 1, 1, 12, 0, i),
          isMe: false,
        );
      }

      expect(store.messages, hasLength(3));
      expect(store.messages.first.msgId, 'srv-2');
      expect(store.messages.last.msgId, 'srv-4');
    });
  });
}
