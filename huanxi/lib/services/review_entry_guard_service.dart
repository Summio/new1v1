import '../core/constants/api_endpoints.dart';
import '../core/network/api_exception.dart';
import '../core/network/dio_client.dart';

class ReviewEntryStatus {
  final bool canEnter;
  final String status;
  final String reasonCode;
  final String msg;

  const ReviewEntryStatus({
    required this.canEnter,
    required this.status,
    required this.reasonCode,
    required this.msg,
  });

  factory ReviewEntryStatus.fromJson(Map<String, dynamic>? json) {
    return ReviewEntryStatus(
      canEnter: json?['can_enter'] == true,
      status: json?['status'] as String? ?? 'none',
      reasonCode: json?['reason_code'] as String? ?? '',
      msg: json?['msg'] as String? ?? '',
    );
  }
}

class ReviewEntryStatusResult {
  final ReviewEntryStatus profileEdit;
  final ReviewEntryStatus momentPublish;

  const ReviewEntryStatusResult({
    required this.profileEdit,
    required this.momentPublish,
  });

  factory ReviewEntryStatusResult.fromJson(Map<String, dynamic> json) {
    return ReviewEntryStatusResult(
      profileEdit: ReviewEntryStatus.fromJson(
        json['profile_edit'] as Map<String, dynamic>?,
      ),
      momentPublish: ReviewEntryStatus.fromJson(
        json['moment_publish'] as Map<String, dynamic>?,
      ),
    );
  }
}

class ReviewEntryGuardService {
  ReviewEntryGuardService._();

  static final ReviewEntryGuardService instance = ReviewEntryGuardService._();

  final DioClient _dio = DioClient.instance;

  Future<ReviewEntryStatusResult> fetchEntryStatus() async {
    final data = await _dio.apiGet(ApiEndpoints.reviewEntryStatus);
    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw const ApiException(code: 500, message: '状态检查失败，请稍后再试');
    }
    return ReviewEntryStatusResult.fromJson(respData);
  }
}
