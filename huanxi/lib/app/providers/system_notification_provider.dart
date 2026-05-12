import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/system_notification_service.dart';

class SystemNotificationUnreadState {
  final int count;
  final SystemNotificationItem? latest;
  final bool isLoading;

  const SystemNotificationUnreadState({
    this.count = 0,
    this.latest,
    this.isLoading = false,
  });

  SystemNotificationUnreadState copyWith({
    int? count,
    SystemNotificationItem? latest,
    bool? isLoading,
  }) {
    return SystemNotificationUnreadState(
      count: count ?? this.count,
      latest: latest ?? this.latest,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SystemNotificationUnreadNotifier
    extends StateNotifier<SystemNotificationUnreadState> {
  SystemNotificationUnreadNotifier()
      : super(const SystemNotificationUnreadState());

  final SystemNotificationService _service =
      SystemNotificationService.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final summary = await _service.fetchUnreadSummary();
      state = SystemNotificationUnreadState(
        count: summary.count,
        latest: summary.latest,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void syncCount(int count) {
    state = state.copyWith(count: count < 0 ? 0 : count);
  }
}

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
  SystemNotificationListNotifier(this._ref)
      : super(const SystemNotificationListState());

  final Ref _ref;
  final SystemNotificationService _service =
      SystemNotificationService.instance;

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
      await _ref.read(systemNotificationUnreadProvider.notifier).refresh();
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
          .map((item) => item.id == notificationId
              ? item.copyWith(isRead: true, readAt: DateTime.now().toString())
              : item)
          .toList(),
    );
    await _ref.read(systemNotificationUnreadProvider.notifier).refresh();
  }

  Future<void> markUnread(int notificationId) async {
    await _service.markUnread(notificationId);
    state = state.copyWith(
      items: state.items
          .map((item) => item.id == notificationId
              ? SystemNotificationItem(
                  id: item.id,
                  content: item.content,
                  type: item.type,
                  publishAt: item.publishAt,
                  isRead: false,
                )
              : item)
          .toList(),
    );
    await _ref.read(systemNotificationUnreadProvider.notifier).refresh();
  }

  Future<void> readAll() async {
    await _service.readAll();
    state = state.copyWith(
      items: state.items
          .map((item) => item.copyWith(
                isRead: true,
                readAt: DateTime.now().toString(),
              ))
          .toList(),
    );
    await _ref.read(systemNotificationUnreadProvider.notifier).refresh();
  }
}

final systemNotificationUnreadProvider =
    StateNotifierProvider<SystemNotificationUnreadNotifier,
        SystemNotificationUnreadState>((ref) {
  return SystemNotificationUnreadNotifier();
});

final systemNotificationListProvider =
    StateNotifierProvider<SystemNotificationListNotifier,
        SystemNotificationListState>((ref) {
  return SystemNotificationListNotifier(ref);
});
