import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/certified_user_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../services/moment_service.dart';
import '../../services/user_home_service.dart';
import 'package:huanxi/core/utils/app_toast.dart';
import 'moment_media_grid.dart';
import 'moment_image_preview_page.dart';
import 'moment_video_preview_page.dart';
import 'main_shell.dart';
import 'user_more_actions.dart';

Color _availabilityColor(String status) {
  switch (status) {
    case 'online':
      return AppTheme.onlineGreen;
    case 'busy':
      return const Color(0xFFFF3B30);
    case 'dnd':
      return const Color(0xFFAF52DE);
    default:
      return AppTheme.offlineGray;
  }
}

/// 认证用户详情页 (Momo 风格)
class CertifiedUserDetailPage extends ConsumerStatefulWidget {
  final CertifiedUserInfo? certifiedUser;
  final int? userId;

  const CertifiedUserDetailPage({super.key, this.certifiedUser, this.userId});

  @override
  ConsumerState<CertifiedUserDetailPage> createState() =>
      _CertifiedUserDetailPageState();
}

class _CertifiedUserDetailPageState
    extends ConsumerState<CertifiedUserDetailPage> {
  int _currentPhotoIndex = 0;
  CertifiedUserInfo? _certifiedUser;
  bool _isLoading = false;
  bool _isFollowLoading = false;
  bool _isFollowing = false;
  bool _blockedByMe = false;
  bool _blockedMe = false;
  bool _interactionBlocked = false;
  String? _error;
  StreamSubscription<PresenceEvent>? _presenceSubscription;

  CertifiedUserInfo? get _resolvedCertifiedUser =>
      _certifiedUser ?? widget.certifiedUser;

  @override
  void initState() {
    super.initState();
    _certifiedUser = widget.certifiedUser;
    _presenceSubscription = MainShell.presenceStream.listen(
      _handlePresenceEvent,
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    super.dispose();
  }

  void _handlePresenceEvent(PresenceEvent event) {
    final current = _resolvedCertifiedUser;
    if (!mounted || current == null || current.userId != event.userId) return;
    setState(() {
      _certifiedUser = current.copyWith(
        isOnline: event.online,
        isBusy: event.isBusy,
        videoDndEnabled: event.videoDndEnabled,
        availabilityStatus: event.availabilityStatus,
        availabilityLabel: event.availabilityLabel,
      );
    });
  }

  Future<void> _openIm({required CertifiedUserInfo certifiedUser}) async {
    if (_interactionBlocked) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('你们之间已存在黑名单关系，无法聊天')),
      );
      return;
    }
    final result = await context.push(
      '${AppRoutes.im}/${certifiedUser.userId}',
      extra: {
        'peerNickname': certifiedUser.username,
        'peerAvatarUrl': certifiedUser.avatar,
      },
    );
    _handleImPageResult(result);
  }

  void _handleImPageResult(dynamic result) {
    if (!mounted) return;
    final message = result is String ? result.trim() : '';
    if (message.isEmpty) return;
    AppToast.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Future<void> _openCall(CertifiedUserInfo certifiedUser) async {
    if (_interactionBlocked) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('你们之间已存在黑名单关系，无法呼叫')),
      );
      return;
    }
    try {
      unawaited(
        context
            .push(
              Uri(
                path: AppRoutes.callOutgoing,
                queryParameters: {
                  'peerUserId': certifiedUser.userId.toString(),
                  'targetUserId': certifiedUser.userId.toString(),
                  'peerName': certifiedUser.username ?? '认证用户',
                  'peerAvatar': certifiedUser.avatar ?? '',
                  'callPrice':
                      certifiedUser.callPrice?.toStringAsFixed(0) ?? '0',
                },
              ).toString(),
            )
            .then(_handleCallPageResult)
            .catchError((_) {
              if (!mounted) return;
              AppToast.showSnackBar(
                context,
                const SnackBar(content: Text('通话启动失败，请稍后重试')),
              );
            }),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('通话启动失败，请稍后重试')),
      );
    }
  }

  void _handleCallPageResult(dynamic result) {
    if (!mounted) return;
    final message = result is String ? result.trim() : '';
    if (message.isEmpty) return;
    AppToast.showSnackBar(context, SnackBar(content: Text(message)));
  }

  void _previewPhoto(List<String> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentImagePreviewPage(
          imageUrl: photos[index],
          imageUrls: photos,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _copyUserId(int userId) async {
    await Clipboard.setData(ClipboardData(text: userId.toString()));
    if (!mounted) return;
    AppToast.showSnackBar(context, const SnackBar(content: Text('ID已复制')));
  }

  Future<void> _loadProfile() async {
    final targetUserId = widget.userId ?? widget.certifiedUser?.userId;
    if (targetUserId == null || targetUserId <= 0) return;

    if (_certifiedUser == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final result = await UserHomeService.instance.getUserHome(targetUserId);
      if (!mounted) return;
      setState(() {
        _certifiedUser = result.certifiedUser;
        _isFollowing = result.isFollowing;
        _blockedByMe = result.certifiedUser.blockedByMe;
        _blockedMe = result.certifiedUser.blockedMe;
        _interactionBlocked = result.certifiedUser.interactionBlocked;
        _isLoading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_certifiedUser == null) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_certifiedUser == null) {
        setState(() {
          _error = '获取主页信息失败';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow(CertifiedUserInfo certifiedUser) async {
    if (_isFollowLoading) return;
    if (_interactionBlocked) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('你们之间已存在黑名单关系，无法关注')),
      );
      return;
    }

    final authState = ref.read(authProvider);
    if (authState.userId != null && authState.userId == certifiedUser.userId) {
      return;
    }

    if (_isFollowing) {
      final name = certifiedUser.username?.trim().isNotEmpty == true
          ? certifiedUser.username!.trim()
          : '用户${certifiedUser.userId}';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认取消关注'),
          content: Text('确定不再关注 $name 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('不再关注'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _isFollowLoading = true;
    });

    try {
      final next = _isFollowing
          ? await UserHomeService.instance.unfollowUser(certifiedUser.userId)
          : await UserHomeService.instance.followUser(certifiedUser.userId);
      if (!mounted) return;
      setState(() {
        _isFollowing = next;
        _isFollowLoading = false;
      });
      AppToast.showSnackBar(
        context,
        SnackBar(content: Text(next ? '已关注' : '已取消关注')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isFollowLoading = false;
      });
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFollowLoading = false;
      });
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('关注操作失败，请稍后重试')),
      );
    }
  }

  Future<void> _openMoreActions(CertifiedUserInfo certifiedUser) async {
    final changed = await showUserMoreActions(
      context: context,
      targetUserId: certifiedUser.userId,
      targetName: certifiedUser.username ?? '用户${certifiedUser.userId}',
      blockedByMe: _blockedByMe,
      blockedMe: _blockedMe,
    );
    if (changed == true) {
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final certifiedUser = _resolvedCertifiedUser;
    final authState = ref.watch(authProvider);
    if (_isLoading && certifiedUser == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (certifiedUser == null) {
      final message = _error ?? '认证用户信息无效，请返回重试';
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppTheme.textHint,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadProfile,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isSelf =
        authState.userId != null && authState.userId == certifiedUser.userId;
    final screenWidth = MediaQuery.of(context).size.width;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final rawHeaderCacheWidth = (screenWidth * devicePixelRatio).round();
    final headerCacheWidth = rawHeaderCacheWidth > 1080
        ? 1080
        : rawHeaderCacheWidth;
    final photos = _detailPhotos(certifiedUser);
    final hasPhotos = photos.isNotEmpty;
    final age = _ageFromBirthDate(certifiedUser.birthDate);
    final zodiac = _zodiacFromBirthDate(certifiedUser.birthDate);

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: isSelf ? null : () => _openMoreActions(certifiedUser),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: screenWidth * 1.2,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  ),
                  if (hasPhotos)
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (index) {
                        setState(() => _currentPhotoIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final photoUrl = photos[index];
                        return GestureDetector(
                          key: ValueKey('certified_user_album_photo_$index'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _previewPhoto(photos, index),
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            cacheWidth: headerCacheWidth,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return _buildHeaderPlaceholder();
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return _buildHeaderPlaceholder();
                            },
                          ),
                        );
                      },
                    )
                  else
                    _buildHeaderPlaceholder(),
                  if (hasPhotos)
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),
                  if (photos.length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 56,
                      child: IgnorePointer(
                        child: _buildPhotoDots(photos.length),
                      ),
                    ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                certifiedUser.username ??
                                    (certifiedUser.isCertifiedUser
                                        ? '认证用户'
                                        : '用户'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ID: ${certifiedUser.userId}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    key: const ValueKey(
                                      'certified_user_id_copy_button',
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () =>
                                        _copyUserId(certifiedUser.userId),
                                    child: const Padding(
                                      padding: EdgeInsets.all(3),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 14,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildTag(
                                    icon: certifiedUser.gender == 'male'
                                        ? Icons.male
                                        : Icons.female,
                                    label: age == null
                                        ? _genderText(certifiedUser.gender)
                                        : '$age岁',
                                    color: const Color(0xFFFF69B4),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTag(
                                    icon: Icons.auto_awesome,
                                    label: zodiac ?? '星座未填',
                                    color: AppTheme.primaryColor,
                                  ),
                                  if ((certifiedUser.status ?? 'normal') ==
                                      'banned') ...[
                                    const SizedBox(width: 8),
                                    _buildTag(
                                      icon: Icons.block_rounded,
                                      label: '封禁',
                                      color: AppTheme.errorColor,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          // 状态必须同时显示颜色和文字，不能只依赖色点。
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _availabilityColor(
                              certifiedUser.availabilityStatus,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _availabilityColor(
                                    certifiedUser.availabilityStatus,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                certifiedUser.availabilityLabel,
                                style: TextStyle(
                                  color: _availabilityColor(
                                    certifiedUser.availabilityStatus,
                                  ),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildInfoChip(
                          icon: Icons.height,
                          label: certifiedUser.heightCm == null
                              ? '身高未填'
                              : '${certifiedUser.heightCm}cm',
                        ),
                        _buildInfoChip(
                          icon: Icons.monitor_weight_outlined,
                          label: certifiedUser.weightKg == null
                              ? '体重未填'
                              : '${certifiedUser.weightKg}kg',
                        ),
                        _buildInfoChip(
                          icon: Icons.location_on_outlined,
                          label: _locationLabel(certifiedUser.locationCity),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_interactionBlocked) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '你们之间已存在黑名单关系，无法互相关注、聊天、通话和送礼',
                          style: TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),
                    const Text(
                      '关于我',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (certifiedUser.signature?.trim().isNotEmpty ?? false)
                          ? certifiedUser.signature!.trim()
                          : '这个用户很懒，还没有填写个性签名哦~',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),
                    _CertifiedUserMomentsSection(userId: certifiedUser.userId),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: isSelf
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (!isSelf) ...[
                      Expanded(
                        flex: 1,
                        child: Tooltip(
                          message: _isFollowing ? '取消关注' : '关注',
                          child: OutlinedButton(
                            onPressed: _isFollowLoading || _interactionBlocked
                                ? null
                                : () => _toggleFollow(certifiedUser),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size(48, 48),
                              side: BorderSide(
                                color: _isFollowing
                                    ? AppTheme.errorColor
                                    : const Color(0xFFFF2D55),
                              ),
                              foregroundColor: _isFollowing
                                  ? AppTheme.errorColor
                                  : const Color(0xFFFF2D55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Icon(
                              _isFollowLoading
                                  ? Icons.hourglass_top_rounded
                                  : (_isFollowing
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: Tooltip(
                          message: '聊一聊',
                          child: OutlinedButton(
                            onPressed: _interactionBlocked
                                ? null
                                : () => _openIm(certifiedUser: certifiedUser),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              minimumSize: const Size(48, 48),
                              side: const BorderSide(
                                color: AppTheme.dividerColor,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!isSelf && certifiedUser.isCertifiedUser)
                      const SizedBox(width: 12),
                    if (certifiedUser.isCertifiedUser)
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: AppTheme.elevatedShadow,
                          ),
                          child: ElevatedButton(
                            onPressed: _interactionBlocked
                                ? null
                                : () => _openCall(certifiedUser),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.videocam,
                                  size: 22,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '立即通话 (${certifiedUser.callPrice?.toStringAsFixed(0) ?? '0'}/分)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderPlaceholder() {
    return Container(
      color: const Color(0xFFEFEFF4),
      child: const Center(
        child: Icon(Icons.person, size: 100, color: AppTheme.primaryColor),
      ),
    );
  }

  Widget _buildPhotoDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == _currentPhotoIndex;
        return AnimatedContainer(
          key: ValueKey('certified_user_album_dot_$index'),
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 7 : 6,
          height: active ? 7 : 6,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _buildTag({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _detailPhotos(CertifiedUserInfo certifiedUser) {
    final seen = <String>{};
    final photos = <String>[];
    for (final item in certifiedUser.albumPhotos) {
      final url = item.trim();
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      photos.add(url);
    }
    return photos;
  }

  int? _ageFromBirthDate(String? value) {
    final birthDate = DateTime.tryParse(value?.trim() ?? '');
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final birthdayPassed =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!birthdayPassed) age -= 1;
    return age < 0 ? null : age;
  }

  String? _zodiacFromBirthDate(String? value) {
    final birthDate = DateTime.tryParse(value?.trim() ?? '');
    if (birthDate == null) return null;
    final month = birthDate.month;
    final day = birthDate.day;
    if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return '白羊座';
    if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return '金牛座';
    if ((month == 5 && day >= 21) || (month == 6 && day <= 21)) return '双子座';
    if ((month == 6 && day >= 22) || (month == 7 && day <= 22)) return '巨蟹座';
    if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return '狮子座';
    if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return '处女座';
    if ((month == 9 && day >= 23) || (month == 10 && day <= 23)) return '天秤座';
    if ((month == 10 && day >= 24) || (month == 11 && day <= 22)) return '天蝎座';
    if ((month == 11 && day >= 23) || (month == 12 && day <= 21)) return '射手座';
    if ((month == 12 && day >= 22) || (month == 1 && day <= 19)) return '摩羯座';
    if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return '水瓶座';
    return '双鱼座';
  }

  String _genderText(String? value) {
    if (value == 'male') return '男';
    if (value == 'female') return '女';
    return '男';
  }

  String _locationLabel(String? value) {
    final city = Formatters.locationCity(value);
    return city.isEmpty ? '所在地未填' : city;
  }
}

class _CertifiedUserMomentsSection extends StatefulWidget {
  final int userId;

  const _CertifiedUserMomentsSection({required this.userId});

  @override
  State<_CertifiedUserMomentsSection> createState() =>
      _CertifiedUserMomentsSectionState();
}

class _CertifiedUserMomentsSectionState
    extends State<_CertifiedUserMomentsSection> {
  late Future<MomentListResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MomentListResult> _load() {
    return MomentService.instance.getUserMoments(userId: widget.userId);
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MomentListResult>(
      future: _future,
      builder: (context, snapshot) {
        final total = snapshot.data?.total ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '动态',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (total > 0)
                  Text(
                    '共$total条',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBody(snapshot),
          ],
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<MomentListResult> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (snapshot.hasError) {
      final message = snapshot.error is ApiException
          ? (snapshot.error as ApiException).message
          : '动态加载失败';
      return InkWell(
        onTap: _retry,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '$message，点击重试',
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final moments = snapshot.data?.rows ?? const <Moment>[];
    if (moments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '还没有发布动态',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < moments.length; i++) ...[
          _CertifiedUserMomentItem(moment: moments[i]),
          if (i != moments.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: AppTheme.dividerColor),
            ),
        ],
      ],
    );
  }
}

class _CertifiedUserMomentItem extends StatelessWidget {
  final Moment moment;

  const _CertifiedUserMomentItem({required this.moment});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (moment.content.trim().isNotEmpty) ...[
          Text(
            moment.content.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (moment.mediaList.isNotEmpty)
          MomentMediaGrid(
            mediaList: moment.mediaList,
            onTap: (index, media) => _openMedia(context, media),
          ),
        const SizedBox(height: 8),
        Text(
          _formatTime(moment.createdAt),
          style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
        ),
      ],
    );
  }

  void _openMedia(BuildContext context, MomentMedia media) {
    final imageUrls = moment.mediaList
        .where((item) => item.mediaType == 1)
        .map((item) => item.url)
        .toList();
    final imageIndex = imageUrls.indexOf(media.url);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => media.mediaType == 2
            ? MomentVideoPreviewPage(videoUrl: media.url)
            : MomentImagePreviewPage(
                imageUrl: media.url,
                imageUrls: imageUrls,
                initialIndex: imageIndex < 0 ? 0 : imageIndex,
              ),
      ),
    );
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
