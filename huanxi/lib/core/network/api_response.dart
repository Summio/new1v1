/// 统一 API 响应格式
/// 与后端 app/schemas/base.py 的 Success / SuccessExtra 对应
class ApiResponse<T> {
  final int code;
  final String msg;
  final T? data;
  final List<dynamic> rows;
  final int current;
  final int total;
  final bool hasMore;

  const ApiResponse({
    required this.code,
    required this.msg,
    this.data,
    this.rows = const [],
    this.current = 1,
    this.total = 0,
    this.hasMore = false,
  });

  bool get isSuccess => code == 200;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json)? fromJsonT,
  ) {
    return ApiResponse(
      code: json['code'] as int? ?? 0,
      msg: json['msg'] as String? ?? '',
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
      rows: (json['rows'] as List<dynamic>?) ?? [],
      current: json['current'] as int? ?? 1,
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'msg': msg,
      'data': data,
      'rows': rows,
      'current': current,
      'total': total,
      'has_more': hasMore,
    };
  }
}
