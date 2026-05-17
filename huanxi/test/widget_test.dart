import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:huanxi/core/network/dio_client.dart';
import 'package:huanxi/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    _ensureDioClientInitialized();
    DioClient.instance.dio.httpClientAdapter = _BootstrapSuccessAdapter();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(child: HuanxiApp()),
    );

    // Just verify the app builds without error.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  });
}

void _ensureDioClientInitialized() {
  try {
    DioClient.instance.dio;
  } catch (_) {
    DioClient.instance.init();
  }
}

class _BootstrapSuccessAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'code': 200,
        'data': {
          'token_names': {'coin_name': '金币', 'diamond_name': '钻石'},
          'im': {'configured': false, 'sdk_app_id': null},
          'customer_service': {
            'enabled': true,
            'user_id': 9001,
            'nickname': '在线客服',
          },
          'im_text_billing': {
            'enabled': false,
            'price': 0,
            'certified_user_share_bps': 5000,
          },
          'certified_call_price_tiers': [0, 100, 200],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
