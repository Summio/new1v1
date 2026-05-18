import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/im/call_trace_message.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/storage/storage.dart';
import '../../services/im_service.dart';

/// 通话记录页面（我的页入口）
/// 数据源：IM 通话留痕消息（custom message: call_trace.v1）
class CallPage extends ConsumerStatefulWidget {
  final bool embedded;

  const CallPage({super.key}) : embedded = false;

  const CallPage.embedded({super.key}) : embedded = true;

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  final IMService _imService = IMService();
  bool _isLoading = true;
  String? _errorMessage;
  int _myAppUserId = 0;
  String _myImUserId = '';
  List<_CallRecordItem> _records = <_CallRecordItem>[];
  final Map<String, V2TimUserFullInfo> _imProfileByUserId =
      <String, V2TimUserFullInfo>{};
  final Map<String, _PeerAppProfile> _appProfileByUserId =
      <String, _PeerAppProfile>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCallRecords(showLoading: true);
    });
  }

  Future<void> _loadCallRecords({required bool showLoading}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final authState = ref.read(authProvider);
      final myUserId = authState.userId ?? StorageService.getUserId();
      if (myUserId == null || myUserId <= 0) {
        throw Exception('登录状态已失效，请重新登录');
      }
      _myAppUserId = myUserId;
      await _loginIm(myUserId);

      final conversations = await _imService.getConversationList(count: 30);
      final c2cConversations = conversations
          .where((item) => (item.userID ?? '').trim().isNotEmpty)
          .where((item) => item.userID != _myImUserId)
          .toList();

      await _loadPeerProfiles(c2cConversations);
      await _loadPeerAppProfiles(c2cConversations);

      final grouped = await Future.wait(
        c2cConversations.map(_buildCallRecordsForConversation),
      );
      final merged = <_CallRecordItem>[for (final list in grouped) ...list];
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (!mounted) return;
      setState(() {
        _records = merged;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '加载通话记录失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginIm(int appUserId) async {
    final sigResponse = await DioClient.instance.get(ApiEndpoints.imUserSig);
    final payload = ResponseParsers.parseUserSigPayload(sigResponse.data);
    final imUserId = 'chat_$appUserId';
    _myImUserId = imUserId;
    await _imService.ensureReady(
      sdkAppId: payload.sdkAppId,
      userId: imUserId,
      userSig: payload.userSig,
    );
  }

  Future<void> _loadPeerProfiles(List<V2TimConversation> conversations) async {
    final ids = conversations
        .map((item) => (item.userID ?? '').trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !_imProfileByUserId.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    final profiles = await _imService.getUsersProfile(userIds: ids);
    _imProfileByUserId.addAll(profiles);
  }

  Future<void> _loadPeerAppProfiles(
    List<V2TimConversation> conversations,
  ) async {
    final targets = conversations
        .map((c) => (c.userID ?? '').trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !_appProfileByUserId.containsKey(id))
        .map((id) => (imUserId: id, appUserId: _extractAppUserId(id)))
        .where((item) => item.appUserId != null && item.appUserId! > 0)
        .toList();

    if (targets.isEmpty) return;

    final results = await Future.wait(
      targets.map((item) async {
        try {
          final res = await DioClient.instance.apiGet(
            ApiEndpoints.userPublic,
            params: {'user_id': item.appUserId},
          );
          final data =
              (res['data'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
          final nickname = (data['nickname'] as String?)?.trim();
          final avatar = _imService.normalizeMediaUrl(
            (data['avatar'] as String?)?.trim(),
          );
          return MapEntry(
            item.imUserId,
            _PeerAppProfile(
              nickname: (nickname?.isNotEmpty ?? false) ? nickname : null,
              avatarUrl: avatar.isNotEmpty ? avatar : null,
            ),
          );
        } catch (_) {
          return null;
        }
      }),
    );

    for (final entry in results) {
      if (entry == null) continue;
      _appProfileByUserId[entry.key] = entry.value;
    }
  }

  Future<List<_CallRecordItem>> _buildCallRecordsForConversation(
    V2TimConversation conversation,
  ) async {
    final peerImUserId = (conversation.userID ?? '').trim();
    if (peerImUserId.isEmpty) return <_CallRecordItem>[];

    final messages = await _imService.getC2CHistoryMessage(
      userId: peerImUserId,
      count: 30,
    );
    if (messages.isEmpty) return <_CallRecordItem>[];

    final peer = _resolvePeerInfo(
      conversation: conversation,
      imUserId: peerImUserId,
    );
    final peerUserId = _extractAppUserId(peerImUserId);
    final seenEventIds = <String>{};
    final records = <_CallRecordItem>[];

    for (final message in messages) {
      final trace = _imService.parseCallTraceMessage(message);
      if (trace == null) continue;
      if (!trace.isFinalResult) continue;
      if (seenEventIds.contains(trace.eventId)) continue;
      seenEventIds.add(trace.eventId);
      records.add(
        _CallRecordItem(
          trace: trace,
          peerUserId: peerUserId,
          peerName: peer.displayName,
          peerAvatarUrl: peer.avatarUrl,
          timestamp: _resolveMessageTime(trace: trace, message: message),
        ),
      );
    }
    return records;
  }

  DateTime _resolveMessageTime({
    required CallTraceMessage trace,
    required V2TimMessage message,
  }) {
    if (trace.ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch(trace.ts * 1000);
    }
    final ts = message.timestamp ?? 0;
    if (ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    }
    return DateTime.now();
  }

  _PeerResolvedInfo _resolvePeerInfo({
    required V2TimConversation conversation,
    required String imUserId,
  }) {
    final appProfile = _appProfileByUserId[imUserId];
    final imProfile = _imProfileByUserId[imUserId];

    final appNickname = appProfile?.nickname?.trim() ?? '';
    if (appNickname.isNotEmpty) {
      return _PeerResolvedInfo(
        displayName: appNickname,
        avatarUrl: appProfile?.avatarUrl,
      );
    }

    final imNickname = imProfile?.nickName?.trim() ?? '';
    if (imNickname.isNotEmpty) {
      return _PeerResolvedInfo(
        displayName: imNickname,
        avatarUrl: _imService.normalizeMediaUrl(imProfile?.faceUrl?.trim()),
      );
    }

    final showName = (conversation.showName ?? '').trim();
    if (showName.isNotEmpty && !_isTechnicalImId(showName)) {
      return _PeerResolvedInfo(
        displayName: showName,
        avatarUrl: _imService.normalizeMediaUrl(conversation.faceUrl?.trim()),
      );
    }

    final appUserId = _extractAppUserId(imUserId);
    final fallbackName = appUserId != null && appUserId > 0
        ? '用户$appUserId'
        : '未知用户';
    final appAvatar = appProfile?.avatarUrl;
    if (appAvatar != null && appAvatar.trim().isNotEmpty) {
      return _PeerResolvedInfo(displayName: fallbackName, avatarUrl: appAvatar);
    }
    return _PeerResolvedInfo(
      displayName: fallbackName,
      avatarUrl: _imService.normalizeMediaUrl(
        conversation.faceUrl?.trim() ?? imProfile?.faceUrl?.trim(),
      ),
    );
  }

  bool _isTechnicalImId(String id) {
    return id.startsWith('chat_');
  }

  int? _extractAppUserId(String imUserId) {
    if (imUserId.startsWith('chat_')) {
      return int.tryParse(imUserId.substring('chat_'.length));
    }
    return int.tryParse(imUserId);
  }

  String _formatRecordTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (isToday) {
      return '$hh:$mm';
    }
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '$month-$day $hh:$mm';
  }

  void _openCallRecordAvatarDetail(_CallRecordItem item) {
    final peerUserId = item.peerUserId;
    if (peerUserId == null || peerUserId <= 0) return;
    context.push('${AppRoutes.certifiedUserDetail}?userId=$peerUserId');
  }

  String _phaseTagText(String phase) {
    switch (phase) {
      case 'dialing':
        return '发起';
      case 'accepted':
        return '已接听';
      case 'rejected':
        return '已拒绝';
      case 'cancelled':
        return '已取消';
      case 'ended':
        return '已结束';
      case 'timeout':
        return '未接听';
      case 'balance_empty':
        return '余额不足';
      case 'force_exit':
        return '已离场';
      default:
        return '通话';
    }
  }

  (IconData, Color) _phaseIcon(CallTraceMessage trace) {
    if (trace.phase == 'timeout' ||
        trace.phase == 'rejected' ||
        trace.phase == 'balance_empty' ||
        trace.phase == 'force_exit') {
      return (Icons.call_missed_rounded, const Color(0xFFFF3B30));
    }
    if (trace.actorUserId == _myAppUserId) {
      return (Icons.call_made_rounded, const Color(0xFF34C759));
    }
    return (Icons.call_received_rounded, const Color(0xFF007AFF));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final isCurrentUserCertified = authState.isCertifiedUser;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: widget.embedded
          ? null
          : AppBar(backgroundColor: Colors.white, title: const Text('通话记录')),
      body: _isLoading
          ? StatusView.loading(message: '正在加载通话记录...')
          : (_errorMessage != null && _records.isEmpty)
          ? StatusView.error(
              message: _errorMessage!,
              onRetry: () => _loadCallRecords(showLoading: true),
            )
          : _records.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withValues(alpha: 0.1),
                          AppTheme.accentColor.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.call,
                      size: 56,
                      color: AppTheme.primaryColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '暂无通话记录',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '去首页找一个认证用户开始通话吧',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.index),
                    icon: const Icon(Icons.explore),
                    label: const Text('去首页找认证用户'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadCallRecords(showLoading: false),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _records.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _records[index];
                  final trace = item.trace;
                  final (icon, iconColor) = _phaseIcon(trace);
                  final detail = trace.detailText(
                    currentUserId: _myAppUserId,
                    isCurrentUserCertified: isCurrentUserCertified,
                    coinName: tokenNames.coinName,
                    diamondName: tokenNames.diamondName,
                  );
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openCallRecordAvatarDetail(item),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: iconColor.withValues(
                                alpha: 0.12,
                              ),
                              backgroundImage:
                                  (item.peerAvatarUrl != null &&
                                      item.peerAvatarUrl!.isNotEmpty)
                                  ? NetworkImage(item.peerAvatarUrl!)
                                  : null,
                              child:
                                  (item.peerAvatarUrl == null ||
                                      item.peerAvatarUrl!.isEmpty)
                                  ? Icon(icon, size: 20, color: iconColor)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.peerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatRecordTime(item.timestamp),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(icon, size: 14, color: iconColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      _phaseTagText(trace.phase),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: iconColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  trace.toDisplayText(
                                    currentUserId: _myAppUserId,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                    height: 1.25,
                                  ),
                                ),
                                if (detail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    detail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textHint,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CallRecordItem {
  final CallTraceMessage trace;
  final int? peerUserId;
  final String peerName;
  final String? peerAvatarUrl;
  final DateTime timestamp;

  const _CallRecordItem({
    required this.trace,
    required this.peerUserId,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.timestamp,
  });
}

class _PeerAppProfile {
  final String? nickname;
  final String? avatarUrl;

  const _PeerAppProfile({this.nickname, this.avatarUrl});
}

class _PeerResolvedInfo {
  final String displayName;
  final String? avatarUrl;

  const _PeerResolvedInfo({required this.displayName, required this.avatarUrl});
}
