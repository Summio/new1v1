class UserSigPayload {
  final String userSig;
  final int sdkAppId;

  const UserSigPayload({
    required this.userSig,
    required this.sdkAppId,
  });
}

class ResponseParsers {
  ResponseParsers._();

  static UserSigPayload parseUserSigPayload(dynamic rawResponse) {
    if (rawResponse is! Map<String, dynamic>) {
      throw const FormatException('响应格式错误');
    }
    final data = rawResponse['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('响应缺少 data 字段');
    }
    final userSigRaw = data['usersig'];
    final sdkAppIdRaw = data['sdk_app_id'];
    final userSig = userSigRaw is String ? userSigRaw.trim() : '';
    final sdkAppId = sdkAppIdRaw is num ? sdkAppIdRaw.toInt() : null;
    if (userSig.isEmpty || sdkAppId == null || sdkAppId <= 0) {
      throw const FormatException('IM 凭证字段缺失');
    }
    return UserSigPayload(userSig: userSig, sdkAppId: sdkAppId);
  }
}
