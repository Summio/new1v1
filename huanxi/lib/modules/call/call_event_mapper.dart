enum CallEndReason {
  rejected,
  timeout,
  cancelled,
  balanceEmpty,
  networkLost,
  peerLeft,
  forceExit,
  normal,
}

class CallMappedEvent {
  final CallEndReason? endReason;
  final bool shouldExit;
  final bool shouldSyncBalance;
  final bool shouldShowGift;
  final bool shouldShowBalanceLow;

  const CallMappedEvent({
    required this.endReason,
    this.shouldExit = false,
    this.shouldSyncBalance = false,
    this.shouldShowGift = false,
    this.shouldShowBalanceLow = false,
  });
}

class CallEventMapper {
  static CallMappedEvent map({
    required String event,
    required Map<String, dynamic> data,
  }) {
    if (event == 'balance_updated') {
      return const CallMappedEvent(endReason: null, shouldSyncBalance: true);
    }
    if (event == 'gift_received' || event == 'gift_sent') {
      return const CallMappedEvent(endReason: null, shouldShowGift: true);
    }
    if (event == 'call_balance_low') {
      return const CallMappedEvent(endReason: null, shouldShowBalanceLow: true);
    }
    if (event == 'call_balance_empty') {
      return const CallMappedEvent(
        endReason: CallEndReason.balanceEmpty,
        shouldExit: true,
      );
    }

    const callEndedEvents = {
      'call_ended',
      'call_cancelled',
      'call_timeout',
      'call_rejected',
    };
    if (!callEndedEvents.contains(event)) {
      return const CallMappedEvent(endReason: null);
    }

    final reasonFromData = (data['end_reason'] as String?)?.trim();
    final reasonFromEvent = (data['reason'] as String?)?.trim();
    final reason = (reasonFromData?.isNotEmpty == true)
        ? reasonFromData!
        : (reasonFromEvent?.isNotEmpty == true)
        ? reasonFromEvent!
        : _defaultReasonByEvent(event);
    return CallMappedEvent(
      endReason: _fromReasonString(reason),
      shouldExit: true,
    );
  }

  static CallEndReason fromLocalReason(String? reason) {
    return _fromReasonString(reason);
  }

  static String _defaultReasonByEvent(String event) {
    switch (event) {
      case 'call_rejected':
        return 'rejected';
      case 'call_timeout':
        return 'timeout';
      case 'call_cancelled':
        return 'cancelled';
      case 'call_balance_empty':
        return 'balance_empty';
      default:
        return 'normal';
    }
  }

  static CallEndReason _fromReasonString(String? reason) {
    switch ((reason ?? '').trim()) {
      case 'rejected':
        return CallEndReason.rejected;
      case 'timeout':
        return CallEndReason.timeout;
      case 'cancelled':
        return CallEndReason.cancelled;
      case 'balance_empty':
        return CallEndReason.balanceEmpty;
      case 'network_lost':
        return CallEndReason.networkLost;
      case 'peer_left':
        return CallEndReason.peerLeft;
      case 'force_exit':
        return CallEndReason.forceExit;
      default:
        return CallEndReason.normal;
    }
  }
}
