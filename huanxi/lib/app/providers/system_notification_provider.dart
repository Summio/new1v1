import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/system_notification_service.dart';

class SystemNotificationListState {
  final List<SystemNotificationItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final String? error;

  const SystemNotificationListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.page = 1,
    this.error,
  });

  SystemNotificationListState copyWith({
    List<SystemNotificationItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? error,
  }) {
    return SystemNotificationListState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: error,
    );
  }
}

class SystemNotificationListNotifier
    extends StateNotifier<SystemNotificationListState> {
  SystemNotificationListNotifier() : super(const SystemNotificationListState());

  final SystemNotificationService _service = SystemNotificationService.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.fetchNotifications(page: 1);
      state = state.copyWith(
        items: result.rows,
        isLoading: false,
        hasMore: result.hasMore,
        page: 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await _service.fetchNotifications(page: nextPage);
      state = state.copyWith(
        items: [...state.items, ...result.rows],
        isLoadingMore: false,
        hasMore: result.hasMore,
        page: nextPage,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> markRead(int notificationId) async {
    await _service.markRead(notificationId);
    state = state.copyWith(
      items: state.items
          .map(
            (item) => item.id == notificationId
                ? item.copyWith(isRead: true, readAt: DateTime.now().toString())
                : item,
          )
          .toList(),
    );
  }

  Future<void> markUnread(int notificationId) async {
    await _service.markUnread(notificationId);
    state = state.copyWith(
      items: state.items
          .map(
            (item) => item.id == notificationId
                ? SystemNotificationItem(
                    id: item.id,
                    content: item.content,
                    type: item.type,
                    publishAt: item.publishAt,
                    isRead: false,
                  )
                : item,
          )
          .toList(),
    );
  }

  Future<void> readAll() async {
    await _service.readAll();
    state = state.copyWith(
      items: state.items
          .map(
            (item) =>
                item.copyWith(isRead: true, readAt: DateTime.now().toString()),
          )
          .toList(),
    );
  }

  void syncDetail(SystemNotificationDetail detail) {
    state = state.copyWith(
      items: state.items
          .map(
            (item) => item.id == detail.id
                ? item.copyWith(isRead: detail.isRead, readAt: detail.readAt)
                : item,
          )
          .toList(),
    );
  }
}

final systemNotificationListProvider =
    StateNotifierProvider<
      SystemNotificationListNotifier,
      SystemNotificationListState
    >((ref) {
      return SystemNotificationListNotifier();
    });
