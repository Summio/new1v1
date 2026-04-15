import 'package:dio/dio.dart';
import '../storage/storage.dart';
import 'api_exception.dart';

/// API 拦截器
/// 负责：1) Token 注入 2) 全局错误处理 3) 错误码路由
class ApiInterceptor extends Interceptor {
  /// 登录页路由路径（用于 401 时跳转）
  final String loginRoutePath;

  /// 充值页路由路径（用于 501 时跳转）
  final String rechargeRoutePath;

  ApiInterceptor({
    this.loginRoutePath = '/login',
    this.rechargeRoutePath = '/profile/recharge',
  });

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

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
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

    // 已经是处理过的 ApiException，直接透传
    if (err.error is ApiException) {
      handler.next(err);
      return;
    }

    handler.next(err);
  }

  /// 处理 Token 失效
  void _handleUnauthorized() {
    StorageService.clearUserData();
    // 路由跳转由调用方处理，这里只清理数据
  }
}
