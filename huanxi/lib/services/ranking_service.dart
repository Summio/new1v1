import '../core/constants/api_endpoints.dart';
import '../core/network/api_exception.dart';
import '../core/network/dio_client.dart';
import '../core/utils/app_logger.dart';
import '../app/providers/ranking_models.dart';

class RankingPage {
  final List<RankingItem> rows;
  final int total;
  final bool hasMore;
  final int appDisplayLimit;
  final String scoreUnit;

  const RankingPage({
    required this.rows,
    required this.total,
    required this.hasMore,
    required this.appDisplayLimit,
    required this.scoreUnit,
  });
}

class RankingService {
  RankingService._();

  static final RankingService instance = RankingService._();

  final DioClient _dio = DioClient.instance;

  Future<RankingPage> getRanking({
    required RankingBoard board,
    required RankingPeriod period,
  }) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.rankingList,
        params: buildRankingQueryParams(board: board, period: period),
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '获取排行榜失败';
        throw ApiException(code: 500, message: msg);
      }
      final rows = data['rows'] as List<dynamic>? ?? [];
      final meta = data['data'] as Map<String, dynamic>? ?? {};
      return RankingPage(
        rows: rows
            .map(
              (item) =>
                  RankingItem.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
        total: (data['total'] as num?)?.toInt() ?? rows.length,
        hasMore: data['has_more'] as bool? ?? false,
        appDisplayLimit: (meta['app_display_limit'] as num?)?.toInt() ?? 20,
        scoreUnit: (meta['score_unit'] as String?)?.trim() ?? board.unit,
      );
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('RankingService.getRanking error: $e');
      throw ApiException(code: 500, message: '获取排行榜失败，请稍后重试');
    }
  }
}
