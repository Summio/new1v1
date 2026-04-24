import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/utils/app_logger.dart';

/// 礼物信息
class GiftInfo {
  final int id;
  final String name;
  final String icon;
  final double price;

  const GiftInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.price,
  });

  factory GiftInfo.fromJson(Map<String, dynamic> json) {
    return GiftInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '',
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
  final int? coins;

  const GiftSendResult({required this.success, this.coins});
}

/// 礼物列表 Provider
class GiftListNotifier extends StateNotifier<GiftListState> {
  final DioClient _dio;

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
  }) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.giftSend,
        data: {'gift_id': giftId, 'anchor_user_id': anchorId},
      );
      final success = data['code'] == 200;
      final coins = (data['data'] as Map<String, dynamic>?)?['coins'] as int?;
      return GiftSendResult(success: success, coins: coins);
    } catch (e) {
      AppLogger.debug('gift._sendGiftInternal error: $e');
      return const GiftSendResult(success: false);
    }
  }

  /// 发送礼物（公开方法，供外部调用）
  Future<GiftSendResult> sendGift({
    required int giftId,
    required int anchorId,
  }) {
    return _sendGiftInternal(giftId: giftId, anchorId: anchorId);
  }
}

/// 礼物列表 Provider
final giftListProvider = StateNotifierProvider<GiftListNotifier, GiftListState>(
  (ref) {
    return GiftListNotifier(DioClient.instance);
  },
);
