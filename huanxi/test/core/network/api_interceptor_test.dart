import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/network/api_interceptor.dart';

void main() {
  group('ApiInterceptor', () {
    test('should transform query and body before request is sent', () {
      final interceptor = ApiInterceptor(
        requestTransformer: _TestRequestTransformer(),
      );
      final handler = _TestRequestHandler();
      final options = RequestOptions(
        path: '/test',
        method: 'POST',
        queryParameters: {'foo': 'bar'},
        data: {'name': 'alice'},
      );

      interceptor.onRequest(options, handler);

      expect(handler.nextOptions, isNotNull);
      expect(handler.nextOptions!.queryParameters['enc_foo'], 'enc_bar');
      expect(handler.nextOptions!.data, {'encrypted': true, 'payload': {'name': 'alice'}});
    });

    test('should emit request and response logs when debug logging is enabled', () {
      final logs = <String>[];
      final interceptor = ApiInterceptor(
        enableDebugLog: true,
        debugLogger: logs.add,
      );
      final requestHandler = _TestRequestHandler();
      final responseHandler = _TestResponseHandler();
      final options = RequestOptions(
        path: '/ping',
        method: 'GET',
        queryParameters: {'q': '1'},
      );

      interceptor.onRequest(options, requestHandler);
      interceptor.onResponse(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'code': 200, 'msg': 'ok', 'data': {'pong': true}},
        ),
        responseHandler,
      );

      expect(logs.any((line) => line.contains('[API][Request]')), isTrue);
      expect(logs.any((line) => line.contains('[API][Response]')), isTrue);
      expect(logs.join('\n'), contains('/ping'));
      expect(logs.join('\n'), contains('pong'));
    });
  });
}

class _TestRequestTransformer extends ApiRequestTransformer {
  @override
  Map<String, dynamic> transformQueryParameters(
    Map<String, dynamic> queryParameters,
    RequestOptions options,
  ) {
    return {
      for (final entry in queryParameters.entries) 'enc_${entry.key}': 'enc_${entry.value}',
    };
  }

  @override
  dynamic transformBody(dynamic body, RequestOptions options) {
    return {
      'encrypted': true,
      'payload': body,
    };
  }
}

class _TestRequestHandler extends RequestInterceptorHandler {
  RequestOptions? nextOptions;

  @override
  void next(RequestOptions requestOptions) {
    nextOptions = requestOptions;
  }
}

class _TestResponseHandler extends ResponseInterceptorHandler {
  Response<dynamic>? nextResponse;

  @override
  void next(Response<dynamic> response) {
    nextResponse = response;
  }
}
