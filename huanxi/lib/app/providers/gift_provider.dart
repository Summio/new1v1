import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_logger.dart';

/// 礼物信息
class GiftInfo {
  final int id;
  final String name;
  final String icon;
  final String svgaUrl;
  final double price;

  const GiftInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.svgaUrl,
    required this.price,
  });

  factory GiftInfo.fromJson(Map<String, dynamic> json) {
    return GiftInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '',
      svgaUrl: json['svga_url'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 礼物列表状态
class GiftListState {
  final List<GiftInfo> gifts;
  final bool isLoading;
  final String? error;

  const GiftListState({
    this.gifts = const [],
    this.isLoading = false,
    this.error,
  });

  GiftListState copyWith({
    List<GiftInfo>? gifts,
    bool? isLoading,
    String? error,
  }) {
    return GiftListState(
      gifts: gifts ?? this.gifts,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// 礼物发送结果
class GiftSendResult {
  final bool success;
  final double? coins;
  final int? quantity;
  final int? unitPrice;
  final int? totalPrice;
  final double? anchorIncomeDiamonds;
  final int? giftId;
  final String? giftName;
  final String? giftIcon;
  final String? svgaUrl;
  final String? msg;

  const GiftSendResult({
    required this.success,
    this.coins,
    this.quantity,
    this.unitPrice,
    this.totalPrice,
    this.anchorIncomeDiamonds,
    this.giftId,
    this.giftName,
    this.giftIcon,
    this.svgaUrl,
    this.msg,
  });
}

double? _parseDouble(dynamic value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// 礼物列表 Provider
class GiftListNotifier extends StateNotifier<GiftListState> {
  final DioClient _dio;
  final Random _random = Random();
  int _requestSeq = 0;

  GiftListNotifier(this._dio) : super(const GiftListState());

  /// 获取礼物列表
  Future<void> fetchGifts() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final data = await _dio.apiGet(ApiEndpoints.giftList);

      final rows = data['rows'] as List<dynamic>? ?? [];

      final gifts = rows.map((e) {
        return GiftInfo.fromJson(Map<String, dynamic>.from(e));
      }).toList();

      state = state.copyWith(gifts: gifts, isLoading: false);
    } catch (e) {
      AppLogger.debug('gift.fetchGifts error: $e');
      state = state.copyWith(isLoading: false, error: '礼物加载失败，请稍后重试');
    }
  }

  /// 发送礼物（内部调用）
  Future<GiftSendResult> _sendGiftInternal({
    required int giftId,
    required int anchorId,
    required int quantity,
    required String scene,
    int? callId,
  }) async {
    _requestSeq++;
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${_requestSeq}_${_random.nextInt(1 << 31)}_${giftId}_${anchorId}_${quantity}_${scene}_${callId ?? 0}';
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.giftSend,
        data: {
          'gift_id': giftId,
          'anchor_user_id': anchorId,
          'quantity': quantity,
          'scene': scene,
          'call_id': callId,
          'request_id': requestId,
        },
      );
      final success = data['code'] == 200;
      final resultData = (data['data'] as Map<String, dynamic>?) ?? const {};
      return GiftSendResult(
        success: success,
        coins: _parseDouble(resultData['coins']),
        quantity: resultData['quantity'] as int?,
        unitPrice: resultData['unit_price'] as int?,
        totalPrice: resultData['total_price'] as int?,
        anchorIncomeDiamonds: _parseDouble(resultData['anchor_income_diamonds']),
        giftId: resultData['gift_id'] as int?,
        giftName: resultData['gift_name'] as String?,
        giftIcon: resultData['gift_icon'] as String?,
        svgaUrl: resultData['svga_url'] as String?,
        msg: resultData['msg'] as String?,
      );
    } on ApiException catch (e) {
      AppLogger.debug(
        'gift._sendGiftInternal api error: ${e.code} ${e.message}',
      );
      return GiftSendResult(success: false, msg: e.message);
    } catch (e) {
      AppLogger.debug('gift._sendGiftInternal error: $e');
      return const GiftSendResult(success: false, msg: '发送失败，请稍后重试');
    }
  }

  /// 发送礼物（公开方法，供外部调用）
  Future<GiftSendResult> sendGift({
    required int giftId,
    required int anchorId,
    int quantity = 1,
    String scene = 'chat',
    int? callId,
  }) {
    return _sendGiftInternal(
      giftId: giftId,
      anchorId: anchorId,
      quantity: quantity,
      scene: scene,
      callId: callId,
    );
  }
}

/// 礼物列表 Provider
final giftListProvider = StateNotifierProvider<GiftListNotifier, GiftListState>(
  (ref) {
    return GiftListNotifier(DioClient.instance);
  },
);
