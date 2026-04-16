import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/storage.dart';
import 'api_exception.dart';

/// 请求转换器扩展点（可用于参数加密、签名等）
abstract class ApiRequestTransformer {
  const ApiRequestTransformer();

  Map<String, dynamic> transformQueryParameters(
    Map<String, dynamic> queryParameters,
    RequestOptions options,
  ) {
    return queryParameters;
  }

  dynamic transformBody(dynamic body, RequestOptions options) {
    return body;
  }
}

/// API 拦截器
/// 负责：1) Token 注入 2) 全局错误处理 3) 错误码路由
class ApiInterceptor extends Interceptor {
  /// 登录页路由路径（用于 401 时跳转）
  final String loginRoutePath;

  /// 充值页路由路径（用于 501 时跳转）
  final String rechargeRoutePath;

  /// 请求转换器（用于预留加密/签名扩展）
  final ApiRequestTransformer? requestTransformer;

  /// 是否打印调试日志
  final bool enableDebugLog;

  /// 日志输出函数，默认使用 debugPrint
  final void Function(String message) debugLogger;

  ApiInterceptor({
    this.loginRoutePath = '/login',
    this.rechargeRoutePath = '/profile/recharge',
    this.requestTransformer,
    this.enableDebugLog = false,
    void Function(String message)? debugLogger,
  }) : debugLogger = debugLogger ?? debugPrint;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 注入 Token
    final token = StorageService.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      options.headers['token'] = token; // 后端自定义要求的 token header
    }

    // 设置 content-type
    if (!options.headers.containsKey('Content-Type')) {
      options.headers['Content-Type'] = 'application/json';
    }

    final queryParameters = options.queryParameters;
    if (requestTransformer != null && queryParameters.isNotEmpty) {
      options.queryParameters =
          requestTransformer!.transformQueryParameters(queryParameters, options);
    }

    final requestData = options.data;
    if (requestTransformer != null && requestData != null) {
      options.data = requestTransformer!.transformBody(requestData, options);
    }

    _logRequest(options);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logResponse(response);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'] as int?;

      // 业务错误处理
      if (code != 200) {
        final msg = data['msg'] as String? ?? '请求失败';

        switch (code) {
          case 401:
            // Token 失效 → 清除本地数据，跳转登录
            _handleUnauthorized();
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: UnauthorizedException(message: msg),
                type: DioExceptionType.badResponse,
                response: response,
              ),
            );
            return;
          case 403:
            // 账号封禁
            final banReason = data['ban_reason'] as String? ?? msg;
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: ForbiddenException(banReason: banReason),
                type: DioExceptionType.badResponse,
                response: response,
              ),
            );
            return;
          case 501:
            // 余额不足
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: const InsufficientBalanceException(),
                type: DioExceptionType.badResponse,
                response: response,
              ),
            );
            return;
          default:
            // 其他错误码，作为 ApiException 抛出
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: ApiException(code: code ?? 0, message: msg),
                type: DioExceptionType.badResponse,
                response: response,
              ),
            );
            return;
        }
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 已处理过的业务/网络异常直接透传
    if (err.error is ApiException || err.error is NetworkException) {
      handler.next(err);
      return;
    }

    // 兼容后端返回 HTTP 非 200 + 业务结构体场景
    final responseData = err.response?.data;
    if (responseData is Map<String, dynamic>) {
      final code = responseData['code'] as int?;
      final msg = responseData['msg'] as String?;
      if (code != null && code != 200) {
        if (code == 401) {
          _handleUnauthorized();
        }
        handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            response: err.response,
            type: DioExceptionType.badResponse,
            error: _mapBusinessCodeToException(code, msg ?? '请求失败', responseData),
          ),
        );
        return;
      }
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: const NetworkException('请求超时，请稍后重试'),
          type: err.type,
        ),
      );
      return;
    }

    if (err.type == DioExceptionType.connectionError) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: const NetworkException('网络连接失败，请检查网络'),
          type: err.type,
        ),
      );
      return;
    }

    // HTTP 层非 200 兜底，避免直接把 422/500 等技术状态暴露给页面
    if (err.type == DioExceptionType.badResponse) {
      final statusCode = err.response?.statusCode ?? 0;
      ApiException apiException;
      switch (statusCode) {
        case 401:
          _handleUnauthorized();
          apiException = const UnauthorizedException();
          break;
        case 403:
          apiException = const ForbiddenException();
          break;
        case 429:
          apiException = const ApiException(code: 429, message: '操作过于频繁，请稍后再试');
          break;
        default:
          if (statusCode >= 500) {
            apiException = ApiException(code: statusCode, message: '服务繁忙，请稍后重试');
          } else {
            apiException = ApiException(code: statusCode, message: '请求参数有误，请检查后重试');
          }
      }

      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: DioExceptionType.badResponse,
          error: apiException,
        ),
      );
      return;
    }

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: const NetworkException('请求失败，请稍后重试'),
      ),
    );
  }

  /// 处理 Token 失效
  void _handleUnauthorized() {
    StorageService.clearUserData();
    // 路由跳转由调用方处理，这里只清理数据
  }

  void _logRequest(RequestOptions options) {
    if (!enableDebugLog) return;
    final uri = options.uri.toString();
    final method = options.method.toUpperCase();
    final body = _safeJson(options.data);
    final query = _safeJson(options.queryParameters);
    debugLogger(
      '[API][Request] $method $uri\n'
      'query: $query\n'
      'body: $body',
    );
  }

  void _logResponse(Response response) {
    if (!enableDebugLog) return;
    final uri = response.requestOptions.uri.toString();
    final method = response.requestOptions.method.toUpperCase();
    final statusCode = response.statusCode ?? -1;
    final body = _safeJson(response.data);
    debugLogger(
      '[API][Response] $method $uri [$statusCode]\n'
      'body: $body',
    );
  }

  ApiException _mapBusinessCodeToException(
    int code,
    String message,
    Map<String, dynamic> payload,
  ) {
    switch (code) {
      case 401:
        return UnauthorizedException(message: message);
      case 403:
        final banReason = payload['ban_reason'] as String? ?? message;
        return ForbiddenException(banReason: banReason);
      case 501:
        return const InsufficientBalanceException();
      default:
        return ApiException(code: code, message: message, data: payload['data']);
    }
  }

  String _safeJson(dynamic value) {
    try {
      if (value == null) return 'null';
      return value is String ? value : jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
