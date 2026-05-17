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

  List<SystemPopupItem> _parsePopupItems(Map<String, dynamic> data) {
    final payload = data['data'];
    final rawItems = payload is Map<String, dynamic> ? payload['items'] : null;
    if (rawItems is! List) {
      return const <SystemPopupItem>[];
    }
    return rawItems
        .whereType<Map>()
        .map(
          (item) => SystemPopupItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0)
        .toList(growable: false);
  }

  Future<List<SystemPopupItem>> fetchStartupPopups(String launchId) async {
    final data = await DioClient.instance.apiPost(
      ApiEndpoints.systemPopupStartup,
      data: {'launch_id': launchId},
    );
    return _parsePopupItems(data);
  }

  Future<List<SystemPopupItem>> fetchPendingPopups() async {
    final data = await DioClient.instance.apiGet(
      ApiEndpoints.systemPopupPending,
    );
    return _parsePopupItems(data);
  }

  Future<void> ackPopup(int popupId) async {
    await DioClient.instance.apiPost(
      '${ApiEndpoints.systemPopupAckBase}/$popupId/ack',
    );
  }
}
