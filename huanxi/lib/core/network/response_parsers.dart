class UserSigPayload {
  final String userSig;
  final int sdkAppId;

  const UserSigPayload({
    required this.userSig,
    required this.sdkAppId,
  });
}

class IMTextChargePayload {
  final bool charged;
  final int price;
  final int anchorIncomeDiamonds;
  final int coins;
  final int diamonds;
  final int receiverUserId;
  final String requestId;

  const IMTextChargePayload({
    required this.charged,
    required this.price,
    required this.anchorIncomeDiamonds,
    required this.coins,
    required this.diamonds,
    required this.receiverUserId,
    required this.requestId,
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

  static IMTextChargePayload parseIMTextChargePayload(dynamic rawResponse) {
    if (rawResponse is! Map<String, dynamic>) {
      throw const FormatException('响应格式错误');
    }
    final data = rawResponse['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('响应缺少 data 字段');
    }
    final chargedRaw = data['charged'];
    final price = _parseInt(data['price']);
    final anchorIncomeDiamonds = _parseInt(data['anchor_income_diamonds']);
    final coins = _parseInt(data['coins']);
    final diamonds = _parseInt(data['diamonds']);
    final receiverUserId = _parseInt(data['receiver_user_id']);
    final requestId = data['request_id'] is String
        ? (data['request_id'] as String).trim()
        : '';
    if (chargedRaw is! bool ||
        price == null ||
        anchorIncomeDiamonds == null ||
        coins == null ||
        diamonds == null ||
        receiverUserId == null ||
        receiverUserId <= 0 ||
        requestId.isEmpty) {
      throw const FormatException('文字消息扣费字段缺失');
    }
    return IMTextChargePayload(
      charged: chargedRaw,
      price: price,
      anchorIncomeDiamonds: anchorIncomeDiamonds,
      coins: coins,
      diamonds: diamonds,
      receiverUserId: receiverUserId,
      requestId: requestId,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
