import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call room keeps remote view Positioned directly under Stack', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final remoteViewMethodStart = text.indexOf('Widget _buildRemoteView({');
    final remoteVideoMethodStart = text.indexOf(
      'Widget _buildRemoteVideo({',
      remoteViewMethodStart,
    );
    final remoteViewMethod = text.substring(
      remoteViewMethodStart,
      remoteVideoMethodStart,
    );

    expect(remoteViewMethod, isNot(contains('Positioned.fill')));
    expect(
      text,
      contains('Positioned.fill(\n                child: RepaintBoundary('),
    );
  });

  test(
    'call room dispose does not read Riverpod providers after unmount starts',
    () {
      final text = File(
        'lib/modules/call/call_room_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      final disposeStart = text.indexOf('  @override\n  void dispose()');
      final disposeEnd = text.indexOf(
        '  @override\n  Widget build',
        disposeStart,
      );
      final disposeBody = text.substring(disposeStart, disposeEnd);

      expect(disposeBody, isNot(contains('ref.read')));
    },
  );

  test('call room keeps call websocket controller alive while on screen', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      text,
      contains('ref.watch(callWsControllerProvider(widget.callId));'),
    );
  });

  test('call room parses websocket exit call_id safely', () {
    final text = File(
      'lib/modules/call/controllers/call_ws_controller.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(text, contains("_asInt(event.data['call_id'])"));
  });

  test('IM and call record pages filter non-final call traces', () {
    final imPageText = File(
      'lib/modules/im/im_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final callPageText = File(
      'lib/modules/home/call_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final imServiceText = File(
      'lib/services/im_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(imPageText, contains('trace != null && !trace.isFinalResult'));
    expect(callPageText, contains('!trace.isFinalResult'));
    expect(imServiceText, contains('!trace.isFinalResult'));
  });

  test(
    'call room dispose releases rtc without provider state notification',
    () {
      final text = File(
        'lib/modules/call/call_room_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        text,
        contains(
          'rtcController.leaveAndRelease(onLog: _log, updateState: false)',
        ),
      );
    },
  );
}
