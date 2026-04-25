import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/media_url.dart';
import '../../services/moment_service.dart';

/// 动态媒体九宫格（图片 + 视频封面）
class MomentMediaGrid extends StatelessWidget {
  final List<MomentMedia> mediaList;
  final void Function(int index, MomentMedia media)? onTap;

  const MomentMediaGrid({super.key, required this.mediaList, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (mediaList.isEmpty) return const SizedBox.shrink();

    final imageCount = mediaList.where((m) => m.mediaType == 1).length;
    final videoList = mediaList.where((m) => m.mediaType == 2).toList();

    if (imageCount == 0 && videoList.isNotEmpty) {
      return _buildSingleVideo(videoList.first);
    }

    if (imageCount > 0 && videoList.isEmpty) {
      return _buildImageGrid(mediaList.where((m) => m.mediaType == 1).toList());
    }

    // 混合：图片 + 视频
    return Column(
      children: [
        _buildImageGrid(mediaList.where((m) => m.mediaType == 1).toList()),
        if (videoList.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildSingleVideo(videoList.first),
        ],
      ],
    );
  }

  Widget _buildSingleVideo(MomentMedia media) {
    final coverUrl = (media.coverUrl ?? '').trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: onTap != null ? () => onTap!(0, media) : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 300,
              maxWidth: constraints.maxWidth,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  if (coverUrl.isNotEmpty)
                    _MediaImage(url: coverUrl, fit: BoxFit.cover)
                  else
                    const SizedBox(
                      height: 220,
                      child: _VideoCoverPlaceholder(),
                    ),
                  if (media.duration != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(media.duration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageGrid(List<MomentMedia> images) {
    final count = images.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (count == 1) {
          return _buildSingleImage(images[0], constraints.maxWidth);
        } else if (count == 2) {
          return Row(
            children: [
              Expanded(
                child: _buildThumbnail(images[0], constraints.maxWidth / 2 - 2),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildThumbnail(images[1], constraints.maxWidth / 2 - 2),
              ),
            ],
          );
        } else if (count == 3) {
          return Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: constraints.maxWidth,
                  child: _buildThumbnail(images[0], constraints.maxWidth),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: _buildThumbnail(
                        images[1],
                        (constraints.maxWidth - 4) / 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _buildThumbnail(
                        images[2],
                        (constraints.maxWidth - 4) / 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else if (count == 4) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildThumbnail(
                      images[0],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildThumbnail(
                      images[1],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _buildThumbnail(
                      images[2],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildThumbnail(
                      images[3],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          // 5张及以上：前4个2×2网格
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildThumbnail(
                      images[0],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildThumbnail(
                      images[1],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _buildThumbnail(
                      images[2],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _buildThumbnail(
                      images[3],
                      constraints.maxWidth / 2 - 2,
                    ),
                  ),
                ],
              ),
              if (count > 4) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _buildThumbnail(
                        images[4],
                        constraints.maxWidth / 3 - 3,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (count > 5)
                      Expanded(
                        child: _buildThumbnail(
                          images[5],
                          constraints.maxWidth / 3 - 3,
                        ),
                      ),
                    if (count > 6)
                      Expanded(
                        child: _buildThumbnail(
                          images[6],
                          constraints.maxWidth / 3 - 3,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildSingleImage(MomentMedia media, double maxWidth) {
    return GestureDetector(
      onTap: onTap != null ? () => onTap!(0, media) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 300, maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _MediaImage(url: media.url, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildThumbnail(MomentMedia media, double size) {
    return GestureDetector(
      onTap: onTap != null
          ? () => onTap!(mediaList.indexOf(media), media)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: size,
          child: _MediaImage(url: media.url, fit: BoxFit.cover),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _VideoCoverPlaceholder extends StatelessWidget {
  const _VideoCoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
        ),
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(
              Icons.movie_outlined,
              color: Color(0x99FFFFFF),
              size: 42,
            ),
          ),
        ],
      ),
    );
  }
}

/// 媒体图片组件，支持本地路径和网络URL
class _MediaImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _MediaImage({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final resolved = toAbsoluteMediaUrl(url);
    if (resolved.isEmpty) return _placeholder();

    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: resolved,
        fit: fit,
        memCacheWidth: 600,
        placeholder: (context, imageUrl) => _placeholder(),
        errorWidget: (context, imageUrl, error) => _placeholder(),
      );
    }

    if (resolved.startsWith('/')) {
      return Image.file(
        File(resolved),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF2F2F7),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Color(0xFFC7C7CC), size: 32),
      ),
    );
  }
}
