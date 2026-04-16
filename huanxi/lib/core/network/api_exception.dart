/// API 异常
class ApiException implements Exception {
  final int code;
  final String message;
  final dynamic data;

  const ApiException({
    required this.code,
    required this.message,
    this.data,
  });

  bool get isUnauthorized => code == 401;
  bool get isForbidden => code == 403;
  bool get isInsufficientBalance => code == 501;
  bool get isSuccess => code == 200;

  @override
  String toString() => message;
}

/// 未登录异常
class UnauthorizedException extends ApiException {
  const UnauthorizedException({super.message = '登录已过期，请重新登录'})
      : super(code: 401);
}

/// 账号封禁异常
class ForbiddenException extends ApiException {
  final String? banReason;

  const ForbiddenException({this.banReason})
      : super(
          code: 403,
          message: '账号已被封禁',
          data: banReason,
        );
}

/// 余额不足异常
class InsufficientBalanceException extends ApiException {
  const InsufficientBalanceException({super.message = '余额不足，请先充值'})
      : super(code: 501);
}

/// 网络异常
class NetworkException implements Exception {
  final String message;

  const NetworkException([this.message = '网络连接失败，请检查网络']);

  @override
  String toString() => message;
}
