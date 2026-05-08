import '../app/providers/anchor_provider.dart';
import '../core/constants/api_endpoints.dart';
import '../core/network/api_exception.dart';
import '../core/network/dio_client.dart';
import '../core/utils/app_logger.dart';

class UserHomeProfile {
  final AnchorInfo anchor;
  final bool isFollowing;

  const UserHomeProfile({required this.anchor, required this.isFollowing});
}

class FollowingUserItem {
  final AnchorInfo user;
  final DateTime? followedAt;

  const FollowingUserItem({required this.user, this.followedAt});
}

class FollowingUsersPage {
  final List<FollowingUserItem> items;
  final int total;
  final bool hasMore;

  const FollowingUsersPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });
}

class UserHomeService {
  UserHomeService._();

  static final UserHomeService instance = UserHomeService._();

  final DioClient _dio = DioClient.instance;

  Future<UserHomeProfile> getUserHome(int userId) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.userPublic,
        params: {'user_id': userId},
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '获取主页信息失败';
        AppLogger.debug('UserHomeService.getUserHome fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        throw ApiException(code: 500, message: '获取主页信息失败');
      }
      return UserHomeProfile(
        anchor: AnchorInfo.fromJson(respData),
        isFollowing: respData['is_following'] as bool? ?? false,
      );
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.getUserHome error: $e');
      throw ApiException(code: 500, message: '获取主页信息失败');
    }
  }

  Future<bool> followUser(int userId) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.userFollow,
        data: {'target_user_id': userId},
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '关注失败';
        AppLogger.debug('UserHomeService.followUser fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>?;
      return respData?['is_following'] as bool? ?? true;
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.followUser error: $e');
      throw ApiException(code: 500, message: '关注失败，请重试');
    }
  }

  Future<bool> unfollowUser(int userId) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        ApiEndpoints.userFollow,
        queryParameters: {'user_id': userId},
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '取消关注失败';
        AppLogger.debug('UserHomeService.unfollowUser fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>?;
      return respData?['is_following'] as bool? ?? false;
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.unfollowUser error: $e');
      throw ApiException(code: 500, message: '取消关注失败，请重试');
    }
  }

  Future<FollowingUsersPage> getFollowingUsers({
    required int page,
    required int pageSize,
    String keyword = '',
  }) {
    return _getFollowUsers(
      endpoint: ApiEndpoints.userFollowingList,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      errorMessage: '获取关注列表失败',
    );
  }

  Future<FollowingUsersPage> getFansUsers({
    required int page,
    required int pageSize,
    String keyword = '',
  }) {
    return _getFollowUsers(
      endpoint: ApiEndpoints.userFansList,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      errorMessage: '获取粉丝列表失败',
    );
  }

  Future<FollowingUsersPage> _getFollowUsers({
    required String endpoint,
    required int page,
    required int pageSize,
    required String keyword,
    required String errorMessage,
  }) async {
    try {
      final data = await _dio.apiGet(
        endpoint,
        params: {
          'page': page,
          'page_size': pageSize,
          'keyword': keyword.trim(),
        },
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? errorMessage;
        AppLogger.debug('UserHomeService._getFollowUsers fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final rows = data['rows'] as List<dynamic>? ?? [];
      final items = rows.map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        return FollowingUserItem(
          user: AnchorInfo.fromJson(map),
          followedAt: DateTime.tryParse(map['followed_at'] as String? ?? ''),
        );
      }).toList();
      return FollowingUsersPage(
        items: items,
        total: (data['total'] as num?)?.toInt() ?? items.length,
        hasMore: data['has_more'] as bool? ?? false,
      );
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService._getFollowUsers error: $e');
      throw ApiException(code: 500, message: errorMessage);
    }
  }
}
