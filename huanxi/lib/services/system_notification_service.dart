import '../core/constants/api_endpoints.dart';
import '../core/network/dio_client.dart';

class SystemNotificationItem {
  final int id;
  final String content;
  final String type;
  final String publishAt;
  final String? readAt;
  final bool isRead;

  const SystemNotificationItem({
    required this.id,
    required this.content,
    required this.type,
    required this.publishAt,
    this.readAt,
    required this.isRead,
  });

  factory SystemNotificationItem.fromJson(Map<String, dynamic> json) {
    return SystemNotificationItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      content: (json['content'] as String?)?.trim() ?? '',
      type: (json['type'] as String?)?.trim() ?? '',
      publishAt: (json['publish_at'] as String?)?.trim() ?? '',
      readAt: (json['read_at'] as String?)?.trim(),
      isRead: json['is_read'] == true,
    );
  }

  SystemNotificationItem copyWith({bool? isRead, String? readAt}) {
    return SystemNotificationItem(
      id: id,
      content: content,
      type: type,
      publishAt: publishAt,
      readAt: readAt ?? this.readAt,
      isRead: isRead ?? this.isRead,
    );
  }
}

class SystemNotificationDetail extends SystemNotificationItem {
  const SystemNotificationDetail({
    required super.id,
    required super.content,
    required super.type,
    required super.publishAt,
    super.readAt,
    required super.isRead,
  });

  factory SystemNotificationDetail.fromJson(Map<String, dynamic> json) {
    final base = SystemNotificationItem.fromJson(json);
    return SystemNotificationDetail(
      id: base.id,
      content: base.content,
      type: base.type,
      publishAt: base.publishAt,
      readAt: base.readAt,
      isRead: base.isRead,
    );
  }
}

class SystemNotificationListResult {
  final List<SystemNotificationItem> rows;
  final int total;
  final bool hasMore;

  const SystemNotificationListResult({
    required this.rows,
    required this.total,
    required this.hasMore,
  });
}

class SystemNotificationService {
  SystemNotificationService._();

  static final SystemNotificationService instance =
      SystemNotificationService._();

  Future<SystemNotificationListResult> fetchNotifications({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await DioClient.instance.apiGet(
      ApiEndpoints.systemNotifications,
      params: {'page': page, 'page_size': pageSize},
    );
    final rowsRaw =
        (data['data'] as List?) ?? (data['rows'] as List?) ?? const [];
    final rows = rowsRaw
        .whereType<Map>()
        .map(
          (item) =>
              SystemNotificationItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0)
        .toList();
    final total =
        int.tryParse('${data['total'] ?? rows.length}') ?? rows.length;
    final hasMore =
        data['has_more'] == true || (page > 0 && page * pageSize < total);
    return SystemNotificationListResult(
      rows: rows,
      total: total,
      hasMore: hasMore,
    );
  }

  Future<SystemNotificationDetail> fetchDetail(int notificationId) async {
    final data = await DioClient.instance.apiGet(
      '${ApiEndpoints.systemNotifications}/$notificationId',
    );
    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return SystemNotificationDetail.fromJson(payload);
  }

  Future<void> markRead(int notificationId) async {
    await DioClient.instance.apiPost(
      '${ApiEndpoints.systemNotifications}/$notificationId/read',
    );
  }

  Future<void> markUnread(int notificationId) async {
    await DioClient.instance.apiPost(
      '${ApiEndpoints.systemNotifications}/$notificationId/unread',
    );
  }

  Future<void> readAll() async {
    await DioClient.instance.apiPost(ApiEndpoints.systemNotificationReadAll);
  }
}
