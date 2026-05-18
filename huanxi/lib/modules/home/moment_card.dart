import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../services/moment_service.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/vip_badge.dart';
import 'moment_image_preview_page.dart';
import 'moment_video_preview_page.dart';
import 'moment_media_grid.dart';

/// 单条动态卡片
class MomentCard extends StatelessWidget {
  final Moment moment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete; // 仅自己的动态可删除
  final bool showReviewStatus;

  const MomentCard({
    super.key,
    required this.moment,
    this.onTap,
    this.onDelete,
    this.showReviewStatus = false,
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
                  child: _UserAvatar(
                    avatar: moment.user?.avatar ?? '',
                    size: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              moment.user?.nickname ?? '未知用户',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (moment.user?.isVip == true) ...[
                            const SizedBox(width: 6),
                            const VipBadge(dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(moment.createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (showReviewStatus) ...[
                        const SizedBox(height: 6),
                        _ReviewStatusChip(status: moment.reviewStatus),
                      ],
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

            if (showReviewStatus &&
                moment.reviewStatus == 'rejected' &&
                (moment.reviewRemark?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 10),
              Text(
                '驳回原因：${moment.reviewRemark!.trim()}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.errorColor,
                  height: 1.4,
                ),
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
}

class _ReviewStatusChip extends StatelessWidget {
  final String status;

  const _ReviewStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    late final String label;
    late final Color color;
    late final Color background;
    switch (normalized) {
      case 'pending':
        label = '待审核';
        color = const Color(0xFFE6A23C);
        background = const Color(0xFFFFF7E6);
        break;
      case 'rejected':
        label = '已驳回';
        color = AppTheme.errorColor;
        background = const Color(0xFFFFEEF0);
        break;
      case 'approved':
        label = '已通过';
        color = const Color(0xFF17A34A);
        background = const Color(0xFFEAF8EE);
        break;
      default:
        label = '未审核';
        color = AppTheme.textSecondary;
        background = const Color(0xFFF2F4F7);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
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
