String callEndReasonText(String? endReason) {
  switch ((endReason ?? '').trim()) {
    case 'rejected':
      return '对方已拒绝';
    case 'timeout':
      return '无人接听，通话超时';
    case 'cancelled':
      return '对方已取消呼叫';
    case 'balance_empty':
      return '余额不足，通话已结束';
    case 'network_lost':
      return '网络中断，通话已结束';
    case 'peer_left':
      return '对方已离开通话';
    case 'force_exit':
      return '对方已离线，通话已结束';
    default:
      return '通话已结束';
  }
}
