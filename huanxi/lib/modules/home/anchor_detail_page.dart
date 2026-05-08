import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/anchor_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../services/moment_service.dart';
import 'package:huanxi/core/utils/app_toast.dart';
import 'moment_media_grid.dart';
import 'moment_image_preview_page.dart';
import 'moment_video_preview_page.dart';

/// 主播详情页 (Momo 风格)
class AnchorDetailPage extends ConsumerStatefulWidget {
  final AnchorInfo anchor;

  const AnchorDetailPage({super.key, required this.anchor});

  @override
  ConsumerState<AnchorDetailPage> createState() => _AnchorDetailPageState();
}

class _AnchorDetailPageState extends ConsumerState<AnchorDetailPage> {
  int _currentPhotoIndex = 0;

  Future<void> _openIm({required AnchorInfo anchor}) async {
    final result = await context.push(
      '${AppRoutes.im}/${anchor.userId}',
      extra: {'peerNickname': anchor.username, 'peerAvatarUrl': anchor.avatar},
    );
    _handleImPageResult(result);
  }

  void _handleImPageResult(dynamic result) {
    if (!mounted) return;
    final message = result is String ? result.trim() : '';
    if (message.isEmpty) return;
    AppToast.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Future<void> _openCall(AnchorInfo anchor) async {
    try {
      unawaited(
        context
            .push(
              Uri(
                path: AppRoutes.callOutgoing,
                queryParameters: {
                  'peerUserId': anchor.userId.toString(),
                  'anchorId': anchor.userId.toString(),
                  'peerName': anchor.username ?? '主播',
                  'peerAvatar': anchor.avatar ?? '',
                  'callPrice': '0',
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

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final screenWidth = MediaQuery.of(context).size.width;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final rawHeaderCacheWidth = (screenWidth * devicePixelRatio).round();
    final headerCacheWidth = rawHeaderCacheWidth > 1080
        ? 1080
        : rawHeaderCacheWidth;
    final photos = _detailPhotos(anchor);
    final hasPhotos = photos.isNotEmpty;
    final age = _ageFromBirthDate(anchor.birthDate);
    final zodiac = _zodiacFromBirthDate(anchor.birthDate);

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
            onPressed: () {},
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
                          key: ValueKey('anchor_album_photo_$index'),
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
                                anchor.username ??
                                    (anchor.isAnchor ? '主播' : '用户'),
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
                                    'ID: ${anchor.userId}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    key: const ValueKey(
                                      'anchor_user_id_copy_button',
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _copyUserId(anchor.userId),
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
                                    icon: anchor.gender == 'male'
                                        ? Icons.male
                                        : Icons.female,
                                    label: age == null
                                        ? _genderText(anchor.gender)
                                        : '$age岁',
                                    color: const Color(0xFFFF69B4),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTag(
                                    icon: Icons.auto_awesome,
                                    label: zodiac ?? '星座未填',
                                    color: AppTheme.primaryColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (anchor.isOnline ?? false)
                                ? AppTheme.onlineGreen.withValues(alpha: 0.1)
                                : AppTheme.offlineGray.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: (anchor.isOnline ?? false)
                                      ? AppTheme.onlineGreen
                                      : AppTheme.offlineGray,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (anchor.isOnline ?? false) ? '在线' : '离线',
                                style: TextStyle(
                                  color: (anchor.isOnline ?? false)
                                      ? AppTheme.onlineGreen
                                      : AppTheme.textSecondary,
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
                          label: anchor.heightCm == null
                              ? '身高未填'
                              : '${anchor.heightCm}cm',
                        ),
                        _buildInfoChip(
                          icon: Icons.monitor_weight_outlined,
                          label: anchor.weightKg == null
                              ? '体重未填'
                              : '${anchor.weightKg}kg',
                        ),
                        _buildInfoChip(
                          icon: Icons.location_on_outlined,
                          label:
                              (anchor.locationCity?.trim().isNotEmpty ?? false)
                              ? anchor.locationCity!.trim()
                              : '所在地未填',
                        ),
                        _buildInfoChip(
                          icon: Icons.verified_user_outlined,
                          label: _statusText(anchor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
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
                      (anchor.signature?.trim().isNotEmpty ?? false)
                          ? anchor.signature!.trim()
                          : '这个主播很懒，还没有填写个性签名哦~',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),
                    _AnchorMomentsSection(userId: anchor.userId),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
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
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => _openIm(anchor: anchor),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 20,
                        color: AppTheme.textPrimary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '聊一聊',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: ElevatedButton(
                    onPressed: () => _openCall(anchor),
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
                        Text(
                          '立即通话 (${anchor.callPrice?.toStringAsFixed(0) ?? '0'}/分)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
          key: ValueKey('anchor_album_dot_$index'),
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

  List<String> _detailPhotos(AnchorInfo anchor) {
    final seen = <String>{};
    final photos = <String>[];
    for (final item in anchor.albumPhotos) {
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
    return '保密';
  }

  String _statusText(AnchorInfo anchor) {
    if (anchor.status == 'banned') return '封禁';
    return (anchor.isOnline ?? false) ? '在线' : '离线';
  }
}

class _AnchorMomentsSection extends StatefulWidget {
  final int userId;

  const _AnchorMomentsSection({required this.userId});

  @override
  State<_AnchorMomentsSection> createState() => _AnchorMomentsSectionState();
}

class _AnchorMomentsSectionState extends State<_AnchorMomentsSection> {
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
          _AnchorMomentItem(moment: moments[i]),
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

class _AnchorMomentItem extends StatelessWidget {
  final Moment moment;

  const _AnchorMomentItem({required this.moment});

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
