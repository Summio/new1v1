import '../core/constants/api_endpoints.dart';
import '../core/network/dio_client.dart';

class SystemPopupItem {
  final int id;
  final String title;
  final String content;
  final String type;
  final String publishAt;

  const SystemPopupItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.publishAt,
  });

  factory SystemPopupItem.fromJson(Map<String, dynamic> json) {
    return SystemPopupItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      title: (json['title'] as String?)?.trim() ?? '',
      content: (json['content'] as String?)?.trim() ?? '',
      type: (json['type'] as String?)?.trim() ?? '',
      publishAt: (json['publish_at'] as String?)?.trim() ?? '',
    );
  }
}

class SystemPopupService {
  SystemPopupService._();

  static final SystemPopupService instance = SystemPopupService._();

  Future<void> ackPopup(int popupId) async {
    await DioClient.instance.apiPost(
      '${ApiEndpoints.systemPopupAckBase}/$popupId/ack',
    );
  }
}
