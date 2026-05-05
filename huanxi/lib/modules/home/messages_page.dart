import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/response_parsers.dart';
import '../../core/storage/storage.dart';
import '../../core/utils/conversation_refresh_throttler.dart';
import '../../services/im_service.dart';
import 'package:huanxi/core/utils/app_toast.dart';

/// 消息页
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  final IMService _imService = IMService();
  static const String _chatPrefix = 'chat';
  bool _isLoading = true;
  String? _myUserId;
  List<V2TimConversation> _conversations = [];
  final Map<String, V2TimUserFullInfo> _profileByUserId = {};
  final Map<String, _PeerAppProfile> _appProfileByUserId = {};
  final ConversationRefreshThrottler _refreshThrottler =
      ConversationRefreshThrottler(interval: const Duration(seconds: 2));
  void Function(int)? _totalUnreadListener;
  Timer? _pendingRefreshTimer;
  bool _isLoadingConversations = false;
  bool _pendingRefreshAfterLoad = false;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  @override
  void dispose() {
    _imService.removeMessageListener(_onMessageReceived);
    if (_totalUnreadListener != null) {
      _imService.removeTotalUnreadListener(_totalUnreadListener!);
    }
    _pendingRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final myUserId = authState.userId ?? StorageService.getUserId();
      if (myUserId == null) {
        throw Exception('登录状态失效，请重新登录');
      }
      await _loginWithPrefix(prefix: _chatPrefix, numericUserId: myUserId);

      _imService.removeMessageListener(_onMessageReceived);
      _imService.addMessageListener(_onMessageReceived);
      _totalUnreadListener ??= _onTotalUnreadChanged;
      _imService.removeTotalUnreadListener(_totalUnreadListener!);
      _imService.addTotalUnreadListener(_totalUnreadListener!);
      await _loadConversations(force: true);
    } catch (e) {
      debugPrint('消息页 IM 初始化失败: $e');
      if (mounted) {
        AppToast.showSnackBar(context, SnackBar(content: Text('消息初始化失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithPrefix({
    required String prefix,
    required int numericUserId,
  }) async {
    final dio = DioClient.instance;
    final response = await dio.get(ApiEndpoints.imUserSig);
    final payload = ResponseParsers.parseUserSigPayload(response.data);
    final userSig = payload.userSig;
    final sdkAppId = payload.sdkAppId;
    final userId = '${prefix}_$numericUserId';

    _myUserId = userId;
    await _imService.ensureReady(
      sdkAppId: sdkAppId,
      userId: userId,
      userSig: userSig,
    );
  }

  bool _isPageVisible() {
    final route = ModalRoute.of(context);
    return route?.isCurrent ?? true;
  }

  void _scheduleConversationsRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (!_isPageVisible()) {
      _pendingRefreshAfterLoad = true;
      return;
    }
    _pendingRefreshTimer?.cancel();
    if (immediate || _refreshThrottler.canRefresh()) {
      unawaited(_loadConversations(force: true));
      return;
    }
    _pendingRefreshTimer = Timer(_refreshThrottler.interval, () {
      if (!mounted || !_isPageVisible()) {
        _pendingRefreshAfterLoad = true;
        return;
      }
      unawaited(_loadConversations(force: true));
    });
  }

  Future<void> _loadConversations({bool force = false}) async {
    if (_isLoadingConversations) {
      _pendingRefreshAfterLoad = true;
      return;
    }
    if (!force && !_refreshThrottler.canRefresh()) {
      _scheduleConversationsRefresh();
      return;
    }

    _pendingRefreshTimer?.cancel();
    _isLoadingConversations = true;
    try {
      final list = await _imService.getConversationList(count: 50);
      final c2c = list
          .whereType<V2TimConversation>()
          .where((c) => (c.userID ?? '').isNotEmpty)
          .where((c) => c.userID != _myUserId)
          .toList();
      if (!mounted) return;
      setState(() {
        _conversations = c2c;
      });
      await _loadPeerProfiles(c2c);
      await _loadPeerAppProfiles(c2c);
    } catch (e) {
      debugPrint('加载会话列表失败: $e');
    } finally {
      _isLoadingConversations = false;
      if (_pendingRefreshAfterLoad) {
        _pendingRefreshAfterLoad = false;
        _scheduleConversationsRefresh(immediate: true);
      }
    }
  }

  Future<void> _loadPeerProfiles(List<V2TimConversation> conversations) async {
    final ids = conversations
        .map((c) => c.userID ?? '')
        .where((id) => id.isNotEmpty)
        .where((id) => !_profileByUserId.containsKey(id))
        .toList();
    if (ids.isEmpty) return;
    try {
      final profiles = await _imService.getUsersProfile(userIds: ids);
      if (!mounted || profiles.isEmpty) return;
      setState(() {
        _profileByUserId.addAll(profiles);
      });
    } catch (e) {
      debugPrint('加载会话用户资料失败: $e');
    }
  }

  Future<void> _loadPeerAppProfiles(
    List<V2TimConversation> conversations,
  ) async {
    final targets = conversations
        .map((c) => c.userID?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .where((id) => !_appProfileByUserId.containsKey(id))
        .map((id) {
          final numId = _extractAppUserId(id);
          return (imUserId: id, userId: numId);
        })
        .where((e) => e.userId != null)
        .toList();
    if (targets.isEmpty) return;

    final results = await Future.wait(
      targets.map((target) async {
        try {
          final data = await DioClient.instance.apiGet(
            ApiEndpoints.userPublic,
            params: {'user_id': target.userId},
          );
          final payload =
              (data['data'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
          final nickname = (payload['nickname'] as String?)?.trim();
          final avatarUrl = _imService.normalizeMediaUrl(
            (payload['avatar'] as String?)?.trim(),
          );
          return MapEntry(
            target.imUserId,
            _PeerAppProfile(
              nickname: (nickname?.isNotEmpty ?? false) ? nickname : null,
              avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
            ),
          );
        } catch (_) {
          return null;
        }
      }),
    );

    if (!mounted) return;
    final mapped = <String, _PeerAppProfile>{};
    for (final entry in results) {
      if (entry != null) mapped[entry.key] = entry.value;
    }
    if (mapped.isEmpty) return;
    setState(() {
      _appProfileByUserId.addAll(mapped);
    });
  }

  void _onMessageReceived(dynamic message) {
    if (!_isPageVisible()) {
      _pendingRefreshAfterLoad = true;
      return;
    }
    debugPrint('[MSG_PAGE] 收到消息，调度会话刷新');
    _scheduleConversationsRefresh();
  }

  void _onTotalUnreadChanged(int totalUnreadCount) {
    if (totalUnreadCount < 0) return;
    if (!_isPageVisible()) {
      _pendingRefreshAfterLoad = true;
      return;
    }
    debugPrint('[MSG_PAGE] 未读数变化: $totalUnreadCount，调度会话刷新');
    _scheduleConversationsRefresh();
  }

  String _displayName(V2TimConversation conv) {
    final userId = conv.userID?.trim() ?? '';
    final appNickname = _appProfileByUserId[userId]?.nickname?.trim() ?? '';
    if (appNickname.isNotEmpty) return appNickname;

    final profileName = _profileByUserId[userId]?.nickName?.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;

    final showName = conv.showName?.trim() ?? '';
    final isTechnicalId = _isTechnicalImId(showName);
    if (showName.isNotEmpty && showName != _myUserId && !isTechnicalId) {
      return showName;
    }
    return '';
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

  String? _avatarUrl(V2TimConversation conv) {
    final userId = conv.userID?.trim() ?? '';
    final appAvatar = _appProfileByUserId[userId]?.avatarUrl?.trim() ?? '';
    if (appAvatar.isNotEmpty) return appAvatar;

    final profileFace = _imService.normalizeMediaUrl(
      _profileByUserId[userId]?.faceUrl?.trim(),
    );
    if (profileFace.isNotEmpty) return profileFace;
    final convFace = _imService.normalizeMediaUrl(conv.faceUrl?.trim());
    if (convFace.isNotEmpty) return convFace;
    return null;
  }

  String _lastText(V2TimConversation conv) {
    final currentUserId = _extractAppUserId(_myUserId ?? '') ?? 0;
    return _imService.buildConversationPreview(
      message: conv.lastMessage,
      currentUserId: currentUserId,
    );
  }

  String _timeText(V2TimConversation conv) {
    final ts = conv.lastMessage?.timestamp;
    if (ts == null || ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '消息',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: -1.0,
          ),
        ),
      ),
      body: _isLoading
          ? StatusView.loading()
          : _conversations.isEmpty
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
                      Icons.chat_bubble_outline_rounded,
                      size: 56,
                      color: AppTheme.primaryColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '暂无消息',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '和主播互动后将在此处收到消息',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadConversations(force: true),
              child: ListView.separated(
                itemCount: _conversations.length,
                separatorBuilder: (_, itemIndex) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final avatarUrl = _avatarUrl(conv);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      backgroundImage: avatarUrl == null
                          ? null
                          : NetworkImage(avatarUrl),
                      child: avatarUrl == null
                          ? const Icon(
                              Icons.person,
                              color: AppTheme.primaryColor,
                            )
                          : null,
                    ),
                    title: Text(
                      _displayName(conv),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _lastText(conv),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _timeText(conv),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textHint,
                          ),
                        ),
                        if ((conv.unreadCount ?? 0) > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${conv.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () async {
                      final userId = conv.userID;
                      if (userId == null || userId.isEmpty) return;
                      final router = GoRouter.of(context);
                      await _imService.cleanC2CUnread(peerUserId: userId);
                      final result = await router.push(
                        '${AppRoutes.im}/$userId',
                        extra: {
                          'peerNickname': _displayName(conv),
                          'peerAvatarUrl': _avatarUrl(conv),
                        },
                      );
                      if (!context.mounted) return;
                      if (result is String && result.trim().isNotEmpty) {
                        AppToast.showSnackBar(
                          context,
                          SnackBar(content: Text(result.trim())),
                        );
                      }
                      await _loadConversations(force: true);
                      await _imService.syncTotalUnreadCount();
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _PeerAppProfile {
  final String? nickname;
  final String? avatarUrl;

  const _PeerAppProfile({this.nickname, this.avatarUrl});
}
