/// API 错误码定义
/// 与后端 app/schemas/base.py 中的 code 保持一致
class ErrorCode {
  ErrorCode._();

  /// 成功
  static const int success = 200;

  /// Token 失效 / 未登录
  static const int unauthorized = 401;

  /// 账号封禁
  static const int forbidden = 403;

  /// 余额不足
  static const int insufficientBalance = 501;

  /// 资源不存在
  static const int notFound = 404;

  /// 服务器错误
  static const int serverError = 500;

  /// 参数错误
  static const int badRequest = 400;
}
