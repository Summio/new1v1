import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'call room keeps remote view full screen and tappable for chrome toggle',
    () {
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
        contains('Positioned.fill(\n                child: GestureDetector('),
      );
      expect(text, contains('behavior: HitTestBehavior.opaque'));
      expect(text, contains('onTap: _toggleCallChrome'));
      expect(
        text,
        contains(
          'child: RepaintBoundary(\n                    child: _buildRemoteView(',
        ),
      );
    },
  );

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

  test(
    'call room recharge entry pushes recharge page and refreshes balance',
    () {
      final text = File(
        'lib/modules/call/call_room_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(text, contains('Future<void> _openRechargePage() async'));
      expect(text, contains('await context.push(AppRoutes.recharge);'));
      expect(text, isNot(contains('context.go(AppRoutes.recharge)')));
      expect(
        text,
        contains('ref.read(authProvider.notifier).refreshBalance();'),
      );
      expect(text, contains("label: '充值'"));
    },
  );

  test('call bottom controls are fixed grid without balance text', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final controlsStart = text.indexOf('class _CallBottomControls');
    final hangupStart = text.indexOf('class _CallHangupButton', controlsStart);
    final controlsText = text.substring(controlsStart, hangupStart);

    expect(controlsText, isNot(contains('SingleChildScrollView')));
    expect(controlsText, isNot(contains('scrollDirection: Axis.horizontal')));
    expect(controlsText, contains('Wrap('));
    expect(controlsText, contains('Icons.account_balance_wallet_outlined'));
    expect(controlsText, contains("label: '充值'"));
    expect(controlsText, isNot(contains('余额')));
    expect(controlsText, isNot(contains('coins')));
  });

  test('call top bar does not show per minute call price', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final topBarStart = text.indexOf('class _CallTopBar');
    final bottomControlsStart = text.indexOf(
      'class _CallBottomControls',
      topBarStart,
    );
    final topBarText = text.substring(topBarStart, bottomControlsStart);

    expect(topBarText, isNot(contains('callPrice')));
    expect(topBarText, isNot(contains('/min')));
  });

  test('call top bar has no in-screen back button', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final topBarStart = text.indexOf('class _CallTopBar');
    final bottomControlsStart = text.indexOf(
      'class _CallBottomControls',
      topBarStart,
    );
    final topBarText = text.substring(topBarStart, bottomControlsStart);

    expect(topBarText, isNot(contains('Icons.arrow_back')));
    expect(topBarText, isNot(contains('onBack')));
    expect(text, isNot(contains('onBack: _endCall')));
  });

  test('call room uses unified chrome visibility for immersive mode', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      text,
      contains(
        'final ValueNotifier<bool> _callChromeVisible = ValueNotifier<bool>(true);',
      ),
    );
    expect(text, contains('void _toggleCallChrome()'));
    expect(text, contains('_callChromeVisible.dispose();'));

    final toggleStart = text.indexOf('void _toggleCallChrome()');
    final toggleEnd = text.indexOf(
      'Future<void> _sendChatMessage()',
      toggleStart,
    );
    final toggleText = text.substring(toggleStart, toggleEnd);
    expect(toggleText, contains('_closeChatInput();'));
    expect(toggleText, contains('_callChromeVisible.value = !visible;'));
  });

  test('call chrome widgets and chat overlay follow chrome visibility', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final topBarCall = text.substring(
      text.indexOf('_CallTopBar('),
      text.indexOf('_CallBottomControls('),
    );
    final bottomCall = text.substring(
      text.indexOf('_CallBottomControls('),
      text.indexOf('_CallHangupButton('),
    );
    final hangupCall = text.substring(
      text.indexOf('_CallHangupButton('),
      text.indexOf('if (rtcState.isLoading)'),
    );
    final overlayLayerStart = text.indexOf('class _CallChatOverlayLayer');
    final chatInputStart = text.indexOf(
      'class _CallChatInputOverlay',
      overlayLayerStart,
    );
    final overlayLayerText = text.substring(overlayLayerStart, chatInputStart);

    expect(topBarCall, contains('callChromeVisible: _callChromeVisible'));
    expect(bottomCall, contains('callChromeVisible: _callChromeVisible'));
    expect(hangupCall, contains('callChromeVisible: _callChromeVisible'));
    expect(overlayLayerText, contains('callChromeVisible'));
    expect(overlayLayerText, contains('if (!isChromeVisible)'));
  });

  test('gift animation overlay is not controlled by chrome visibility', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final giftStart = text.indexOf('Widget _buildGiftAnimationOverlay');
    final chatOverlayStart = text.indexOf('Widget _buildChatMessageOverlay');
    final giftText = text.substring(giftStart, chatOverlayStart);

    expect(giftText, isNot(contains('_callChromeVisible')));
    expect(giftText, isNot(contains('callChromeVisible')));
  });

  test('small preview tap only swaps video windows', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final previewPositionStart = text.indexOf(
      'top: MediaQuery.paddingOf(context).top + 16',
    );
    final topBarStart = text.indexOf('_CallTopBar(', previewPositionStart);
    final previewText = text.substring(previewPositionStart, topBarStart);

    expect(previewText, contains('_isRemoteInMainView = !_isRemoteInMainView'));
    expect(previewText, isNot(contains('_toggleCallChrome')));
    expect(previewText, isNot(contains('_callChromeVisible')));
  });

  test('call bottom controls use text label and recharge text gift order', () {
    final text = File(
      'lib/modules/call/call_room_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final controlsStart = text.indexOf('class _CallBottomControls');
    final hangupStart = text.indexOf('class _CallHangupButton', controlsStart);
    final controlsText = text.substring(controlsStart, hangupStart);
    final rechargeIndex = controlsText.indexOf("label: '充值'");
    final textIndex = controlsText.indexOf("label: '文字'");
    final giftIndex = controlsText.indexOf("label: '礼物'");
    expect(textIndex, greaterThanOrEqualTo(0));

    final textButtonStart = controlsText.lastIndexOf(
      '_ControlButton(',
      textIndex,
    );
    final textButtonEnd = controlsText.indexOf('),', textIndex);
    final textButton = controlsText.substring(textButtonStart, textButtonEnd);

    expect(controlsText, isNot(contains("label: '聊天'")));
    expect(controlsText, isNot(contains("'聊天中'")));
    expect(rechargeIndex, greaterThanOrEqualTo(0));
    expect(textIndex, greaterThan(rechargeIndex));
    expect(giftIndex, greaterThan(textIndex));
    expect(textButton, contains('icon: Icons.chat_bubble_outline'));
    expect(textButton, contains('onTap: onToggleChat'));
  });
}
