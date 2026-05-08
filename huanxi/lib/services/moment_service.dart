import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../core/constants/api_endpoints.dart';
import '../core/media/image_upload_preprocessor.dart';
import '../core/network/api_exception.dart';
import '../core/utils/app_logger.dart';

/// 动态媒体模型
class MomentMedia {
  final int id;
  final String url;
  final int mediaType; // 1=图片, 2=视频
  final int sortOrder;
  final String? coverUrl;
  final int? duration;

  MomentMedia({
    required this.id,
    required this.url,
    required this.mediaType,
    this.sortOrder = 0,
    this.coverUrl,
    this.duration,
  });

  factory MomentMedia.fromJson(Map<String, dynamic> json) {
    return MomentMedia(
      id: json['id'] as int? ?? 0,
      url: json['url'] as String? ?? '',
      mediaType: json['media_type'] as int? ?? 1,
      sortOrder: json['sort_order'] as int? ?? 0,
      coverUrl: json['cover_url'] as String?,
      duration: json['duration'] as int?,
    );
  }
}

/// 动态用户信息
class MomentUser {
  final int id;
  final String nickname;
  final String avatar;

  MomentUser({required this.id, required this.nickname, this.avatar = ''});

  factory MomentUser.fromJson(Map<String, dynamic> json) {
    return MomentUser(
      id: json['id'] as int? ?? 0,
      nickname: json['nickname'] as String? ?? '未知用户',
      avatar: json['avatar'] as String? ?? '',
    );
  }
}

/// 动态条目
class Moment {
  final int id;
  final int userId;
  final String content;
  final String? createdAt;
  final List<MomentMedia> mediaList;
  final MomentUser? user;

  Moment({
    required this.id,
    required this.userId,
    this.content = '',
    this.createdAt,
    this.mediaList = const [],
    this.user,
  });

  factory Moment.fromJson(Map<String, dynamic> json) {
    return Moment(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String?,
      mediaList:
          (json['media_list'] as List<dynamic>?)
              ?.map((e) => MomentMedia.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      user: json['user'] != null
          ? MomentUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 分页动态列表
class MomentListResult {
  final List<Moment> rows;
  final int total;
  final bool hasMore;

  MomentListResult({
    this.rows = const [],
    this.total = 0,
    this.hasMore = false,
  });
}

/// 动态服务
class MomentService {
  MomentService._();
  static final MomentService _instance = MomentService._();
  static MomentService get instance => _instance;

  final DioClient _dio = DioClient.instance;

  /// 上传媒体文件（图片或视频），返回 media_id 和 url
  Future<Map<String, dynamic>?> uploadMedia({
    required List<int> bytes,
    required String filename,
    required int mediaType, // 1=图片, 2=视频
    List<int>? coverBytes,
    String? coverFilename,
    int? duration,
  }) async {
    try {
      final preparedFile = mediaType == 1
          ? await ImageUploadPreprocessor.instance.prepareImage(
              bytes: bytes,
              filename: filename,
              scene: ImageUploadScene.momentImage,
            )
          : null;
      final preparedCover = coverBytes != null && coverBytes.isNotEmpty
          ? await ImageUploadPreprocessor.instance.prepareImage(
              bytes: coverBytes,
              filename: (coverFilename?.trim().isNotEmpty ?? false)
                  ? coverFilename!.trim()
                  : 'cover.jpg',
              scene: ImageUploadScene.momentCover,
            )
          : null;
      AppLogger.debug(
        'MomentService.uploadMedia: $filename, mediaType=$mediaType, '
        'bytes=${bytes.length}, uploadBytes=${preparedFile?.bytes.length ?? bytes.length}, '
        'coverBytes=${coverBytes?.length ?? 0}, '
        'uploadCoverBytes=${preparedCover?.bytes.length ?? coverBytes?.length ?? 0}',
      );
      final formMap = <String, dynamic>{
        'file': MultipartFile.fromBytes(
          preparedFile?.bytes ?? bytes,
          filename: preparedFile?.filename ?? filename,
        ),
        'media_type': mediaType,
      };
      if (mediaType == 2 &&
          preparedCover != null &&
          preparedCover.bytes.isNotEmpty) {
        formMap['cover_file'] = MultipartFile.fromBytes(
          preparedCover.bytes,
          filename: preparedCover.filename,
        );
      }
      if (mediaType == 2 && duration != null && duration > 0) {
        formMap['duration'] = duration;
      }

      final formData = FormData.fromMap(formMap);
      final resp = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.momentUpload,
        data: formData,
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '上传失败';
        AppLogger.debug('MomentService.uploadMedia fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return null;
      final id = respData['id'] as int?;
      final url = respData['url'] as String?;
      AppLogger.debug('MomentService.uploadMedia success: id=$id, url=$url');
      if (id == null || url == null) return null;
      return {'id': id, 'url': url.trim()};
    } on ImageUploadPreprocessException catch (e) {
      AppLogger.debug(
        'MomentService.uploadMedia preprocess error: ${e.message}',
      );
      throw ApiException(code: 500, message: e.message);
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.uploadMedia error: $e');
      throw ApiException(code: 500, message: '上传失败，请重试');
    }
  }

  /// 发布动态
  Future<Moment?> createMoment({
    required String content,
    required List<int> mediaIds,
  }) async {
    try {
      AppLogger.debug(
        'MomentService.createMoment: content=$content, mediaIds=$mediaIds',
      );
      final data = await _dio.apiPost(
        ApiEndpoints.momentCreate,
        data: {'content': content, 'media_ids': mediaIds},
      );
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '发布失败';
        AppLogger.debug('MomentService.createMoment fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return null;
      return Moment.fromJson(respData);
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.createMoment error: $e');
      throw ApiException(code: 500, message: '发布失败，请重试');
    }
  }

  /// 获取全局动态列表
  Future<MomentListResult> getFeed({int page = 1, int pageSize = 20}) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.momentFeed,
        params: {'page': page, 'page_size': pageSize},
      );
      final rows =
          (data['rows'] as List<dynamic>?)
              ?.map((e) => Moment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final total = data['total'] as int? ?? 0;
      final hasMore = data['has_more'] as bool? ?? false;
      return MomentListResult(rows: rows, total: total, hasMore: hasMore);
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.getFeed error: $e');
      throw ApiException(code: 500, message: '获取动态列表失败');
    }
  }

  /// 获取我的动态列表
  Future<MomentListResult> getMyMoments({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.momentMine,
        params: {'page': page, 'page_size': pageSize},
      );
      final rows =
          (data['rows'] as List<dynamic>?)
              ?.map((e) => Moment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final total = data['total'] as int? ?? 0;
      final hasMore = data['has_more'] as bool? ?? false;
      return MomentListResult(rows: rows, total: total, hasMore: hasMore);
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.getMyMoments error: $e');
      throw ApiException(code: 500, message: '获取我的动态失败');
    }
  }

  /// 获取指定用户动态列表
  Future<MomentListResult> getUserMoments({
    required int userId,
    int page = 1,
    int pageSize = 3,
  }) async {
    try {
      final data = await _dio.apiGet(
        ApiEndpoints.momentUser,
        params: {'user_id': userId, 'page': page, 'page_size': pageSize},
      );
      final rows =
          (data['rows'] as List<dynamic>?)
              ?.map((e) => Moment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final total = data['total'] as int? ?? 0;
      final hasMore = data['has_more'] as bool? ?? false;
      return MomentListResult(rows: rows, total: total, hasMore: hasMore);
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.getUserMoments error: $e');
      throw ApiException(code: 500, message: '获取用户动态失败');
    }
  }

  /// 删除动态
  Future<bool> deleteMoment(int momentId) async {
    try {
      final resp = await _dio.delete<Map<String, dynamic>>(
        '${ApiEndpoints.momentDelete}/$momentId',
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        final msg = data['msg'] as String? ?? '删除失败';
        AppLogger.debug('MomentService.deleteMoment fail: $msg');
        throw ApiException(code: 500, message: msg);
      }
      return true;
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.debug('MomentService.deleteMoment error: $e');
      throw ApiException(code: 500, message: '删除失败，请重试');
    }
  }
}
