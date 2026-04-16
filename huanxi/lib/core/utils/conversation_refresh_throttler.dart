class ConversationRefreshThrottler {
  final Duration interval;
  DateTime? _lastRefreshAt;

  ConversationRefreshThrottler({
    this.interval = const Duration(seconds: 2),
  });

  bool canRefresh({DateTime? now}) {
    final current = now ?? DateTime.now();
    final last = _lastRefreshAt;
    if (last == null || current.difference(last) >= interval) {
      _lastRefreshAt = current;
      return true;
    }
    return false;
  }
}
