import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huanxi/modules/beauty/beauty_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mt_plugin');
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setChin should send SET_CHIN_TRIMMING_VALUE to native', () async {
    final controller = BeautyController();
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    controller.setChin(23);

    expect(
      calls.any((call) => call.method == 'SET_CHIN_TRIMMING_VALUE'),
      isTrue,
    );
  });

  test('setForehead should send SET_FOREHEAD_TRIMMING_VALUE to native', () async {
    final controller = BeautyController();
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    controller.setForehead(34);

    expect(
      calls.any((call) => call.method == 'SET_FOREHEAD_TRIMMING_VALUE'),
      isTrue,
    );
  });

  test('setNoseThinning should send SET_NOSE_THINNING_VALUE to native', () async {
    final controller = BeautyController();
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    controller.setNoseThinning(45);

    expect(
      calls.any((call) => call.method == 'SET_NOSE_THINNING_VALUE'),
      isTrue,
    );
  });
}
