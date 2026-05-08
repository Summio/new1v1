import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../services/moment_service.dart';
import '../../app/theme/app_theme.dart';
import 'moment_image_preview_page.dart';
import 'moment_video_preview_page.dart';
import 'moment_media_grid.dart';

/// 单条动态卡片
class MomentCard extends StatelessWidget {
  final Moment moment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete; // 仅自己的动态可删除

  const MomentCard({
    super.key,
    required this.moment,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息行
            Row(
              children: [
                // 头像
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: moment.userId > 0
                      ? () {
                          context.push(
                            Uri(
                              path: AppRoutes.certifiedUserDetail,
                              queryParameters: {
                                'userId': moment.userId.toString(),
                              },
                            ).toString(),
                          );
                        }
                      : null,
                  child: _UserAvatar(avatar: moment.user?.avatar ?? '', size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        moment.user?.nickname ?? '未知用户',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(moment.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 删除按钮（仅自己的动态）
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: AppTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),

            // 文本内容
            if (moment.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                moment.content,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // 媒体
            if (moment.mediaList.isNotEmpty) ...[
              const SizedBox(height: 12),
              MomentMediaGrid(
                mediaList: moment.mediaList,
                onTap: (index, media) {
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
                },
              ),
            ],

            // 底部：时间 + 操作行（后续可扩展点赞/评论）
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatDate(moment.createdAt),
                style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  String _formatDate(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

/// 用户头像
class _UserAvatar extends StatelessWidget {
  final String avatar;
  final double size;

  const _UserAvatar({required this.avatar, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceColor,
      ),
      child: ClipOval(
        child: avatar.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: (size * 2).toInt(),
                placeholder: (context, url) => _defaultAvatar(),
                errorWidget: (context, url, error) => _defaultAvatar(),
              )
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      width: size,
      height: size,
      color: AppTheme.surfaceColor,
      child: Icon(Icons.person, size: size * 0.5, color: AppTheme.textHint),
    );
  }
}
