import '../app/providers/certified_user_provider.dart';
import '../core/constants/api_endpoints.dart';
import '../core/network/api_exception.dart';
import '../core/network/dio_client.dart';
import '../core/utils/app_logger.dart';

class UserHomeProfile {
  final CertifiedUserInfo certifiedUser;
  final bool isFollowing;

  const UserHomeProfile({
    required this.certifiedUser,
    required this.isFollowing,
  });
}

class FollowingUserItem {
  final CertifiedUserInfo user;
  final DateTime? followedAt;
  final DateTime? blockedAt;

  const FollowingUserItem({required this.user, this.followedAt, this.blockedAt});
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
        certifiedUser: CertifiedUserInfo.fromJson(respData),
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

  Future<UserBlockStatus> getUserBlockStatus(int userId) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.userBlockStatus,
        params: {'user_id': userId},
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '获取黑名单状态失败';
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>? ?? {};
      return UserBlockStatus.fromJson(respData);
    } on ApiException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.getUserBlockStatus error: $e');
      throw ApiException(code: 500, message: '获取黑名单状态失败');
    }
  }

  Future<bool> blockUser(int userId) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.userBlock,
        data: {'target_user_id': userId},
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '拉黑失败';
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>? ?? {};
      return respData['is_blocked'] as bool? ?? true;
    } on ApiException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.blockUser error: $e');
      throw ApiException(code: 500, message: '拉黑失败，请重试');
    }
  }

  Future<bool> unblockUser(int userId) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        ApiEndpoints.userBlock,
        queryParameters: {'user_id': userId},
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '解除拉黑失败';
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>? ?? {};
      return respData['is_blocked'] as bool? ?? false;
    } on ApiException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.unblockUser error: $e');
      throw ApiException(code: 500, message: '解除拉黑失败，请重试');
    }
  }

  Future<void> createComplaint({
    required int targetUserId,
    required String reason,
    required String content,
  }) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.complaintCreate,
        data: {
          'target_user_id': targetUserId,
          'reason': reason,
          'content': content,
        },
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '投诉提交失败';
        throw ApiException(code: 500, message: msg);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      AppLogger.debug('UserHomeService.createComplaint error: $e');
      throw ApiException(code: 500, message: '投诉提交失败，请重试');
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

  Future<FollowingUsersPage> getBlockedUsers({
    required int page,
    required int pageSize,
    String keyword = '',
  }) {
    return _getFollowUsers(
      endpoint: ApiEndpoints.userBlockList,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      errorMessage: '获取黑名单失败',
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
          user: CertifiedUserInfo.fromJson(map),
          followedAt: DateTime.tryParse(map['followed_at'] as String? ?? ''),
          blockedAt: DateTime.tryParse(map['blocked_at'] as String? ?? ''),
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

class UserBlockStatus {
  final int targetUserId;
  final bool blockedByMe;
  final bool blockedMe;
  final bool interactionBlocked;

  const UserBlockStatus({
    required this.targetUserId,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.interactionBlocked = false,
  });

  factory UserBlockStatus.fromJson(Map<String, dynamic> json) {
    return UserBlockStatus(
      targetUserId: (json['target_user_id'] as num?)?.toInt() ?? 0,
      blockedByMe: json['blocked_by_me'] as bool? ?? false,
      blockedMe: json['blocked_me'] as bool? ?? false,
      interactionBlocked: json['interaction_blocked'] as bool? ?? false,
    );
  }
}
