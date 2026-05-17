import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/auth_provider.dart';
import 'package:huanxi/core/constants/api_endpoints.dart';
import 'package:huanxi/core/network/dio_client.dart';

void main() {
  test('AppInitState parses customer service bootstrap config', () {
    final state = AppInitState.fromBootstrapMap({
      'token_names': {'coin_name': '金币', 'diamond_name': '钻石'},
      'im': {'configured': true, 'sdk_app_id': 12345},
      'customer_service': {
        'enabled': true,
        'user_id': 9001,
        'nickname': '在线客服',
        'avatar': 'https://example.com/avatar.png',
      },
      'im_text_billing': {
        'enabled': false,
        'price': 0,
        'certified_user_share_bps': 5000,
      },
      'certified_call_price_tiers': [0, 100, 200],
    });

    expect(state.coinName, '金币');
    expect(state.diamondName, '钻石');
    expect(state.imConfigured, isTrue);
    expect(state.imSdkAppId, 12345);
    expect(state.customerServiceEnabled, isTrue);
    expect(state.customerServiceUserId, '9001');
    expect(state.customerServiceNickname, '在线客服');
    expect(state.customerServiceAvatar, 'https://example.com/avatar.png');
  });

  test('AppInitNotifier retries bootstrap after a failed load', () async {
    final adapter = _BootstrapAdapter([
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.appBootstrap),
        type: DioExceptionType.connectionError,
        error: 'network unavailable',
      ),
      {
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
          'certified_call_price_tiers': [0, 150, 300],
        },
      },
    ]);
    _ensureDioClientInitialized();
    DioClient.instance.dio.httpClientAdapter = adapter;
    final notifier = AppInitNotifier(DioClient.instance);

    await notifier.init();

    expect(adapter.requestCount, 1);
    expect(notifier.state.loaded, isFalse);
    expect(notifier.state.customerServiceEnabled, isFalse);
    expect(notifier.state.certifiedCallPriceTiers, isEmpty);

    await notifier.init();

    expect(adapter.requestCount, 2);
    expect(notifier.state.loaded, isTrue);
    expect(notifier.state.customerServiceEnabled, isTrue);
    expect(notifier.state.customerServiceUserId, '9001');
    expect(notifier.state.certifiedCallPriceTiers, [0, 150, 300]);
  });

  test('AppInitNotifier waits for an in-flight bootstrap load', () async {
    final releaseResponse = Completer<void>();
    final adapter = _BlockingBootstrapAdapter(
      releaseResponse: releaseResponse,
      response: {
        'code': 200,
        'data': {
          'token_names': {'coin_name': '金币', 'diamond_name': '钻石'},
          'im': {'configured': false, 'sdk_app_id': null},
          'customer_service': {
            'enabled': true,
            'user_id': 9002,
            'nickname': '在线客服',
          },
          'im_text_billing': {
            'enabled': false,
            'price': 0,
            'certified_user_share_bps': 5000,
          },
          'certified_call_price_tiers': [0, 200, 400],
        },
      },
    );
    _ensureDioClientInitialized();
    DioClient.instance.dio.httpClientAdapter = adapter;
    final notifier = AppInitNotifier(DioClient.instance);

    final firstLoad = notifier.init();
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.isLoading, isTrue);

    var secondLoadCompleted = false;
    final secondLoad = notifier.init().then((_) {
      secondLoadCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(secondLoadCompleted, isFalse);
    expect(adapter.requestCount, 1);

    releaseResponse.complete();
    await Future.wait([firstLoad, secondLoad]);

    expect(secondLoadCompleted, isTrue);
    expect(adapter.requestCount, 1);
    expect(notifier.state.loaded, isTrue);
    expect(notifier.state.customerServiceUserId, '9002');
    expect(notifier.state.certifiedCallPriceTiers, [0, 200, 400]);
  });
}

void _ensureDioClientInitialized() {
  try {
    DioClient.instance.dio;
  } catch (_) {
    DioClient.instance.init();
  }
}

class _BootstrapAdapter implements HttpClientAdapter {
  final List<Object> responses;
  int requestCount = 0;

  _BootstrapAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, ApiEndpoints.appBootstrap);
    final response = responses[requestCount.clamp(0, responses.length - 1)];
    requestCount += 1;
    if (response is DioException) {
      throw response;
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BlockingBootstrapAdapter implements HttpClientAdapter {
  final Completer<void> releaseResponse;
  final Map<String, dynamic> response;
  int requestCount = 0;

  _BlockingBootstrapAdapter({
    required this.releaseResponse,
    required this.response,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, ApiEndpoints.appBootstrap);
    requestCount += 1;
    await releaseResponse.future;
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
