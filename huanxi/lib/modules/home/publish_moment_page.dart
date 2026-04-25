import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/moment_provider.dart';
import '../../core/media/video_upload_preprocessor.dart';
import '../../core/utils/app_toast.dart';
import 'moment_video_preview_page.dart';
import '../../services/moment_service.dart';

/// 发布动态页面
class PublishMomentPage extends ConsumerStatefulWidget {
  const PublishMomentPage({super.key});

  @override
  ConsumerState<PublishMomentPage> createState() => _PublishMomentPageState();
}

class _PublishMomentPageState extends ConsumerState<PublishMomentPage> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<_MediaItem> _selectedMedias = []; // 已选择待上传的媒体
  final List<int> _uploadedMediaIds = []; // 已上传成功的 media_id
  final bool _isUploading = false;
  bool _isPublishing = false;
  bool _isPreparingVideo = false;

  void _showToast(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  void _showErrorToast(Object error) {
    if (!mounted) return;
    AppToast.error(context, error);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(),
        ),
        title: const Text('发布动态'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _canPublish ? () => _publish() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: AppTheme.textHint.withValues(
                  alpha: 0.3,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _isPublishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '发布',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 文字输入
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _contentController,
                      maxLines: 8,
                      minLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: '分享这一刻...',
                        hintStyle: const TextStyle(color: AppTheme.textHint),
                        border: InputBorder.none,
                        counterStyle: const TextStyle(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      style: const TextStyle(fontSize: 16, height: 1.5),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),

                  const Divider(height: 1),

                  // 已上传媒体预览
                  if (_uploadedMediaIds.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppTheme.onlineGreen,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '已上传 ${_uploadedMediaIds.length} 个媒体',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 媒体选择区
                  _buildMediaSelector(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canPublish {
    final content = _contentController.text.trim();
    final hasVideoWithoutCover = _selectedMedias.any(
      (m) => m.mediaType == 2 && m.coverBytes == null,
    );
    return (content.isNotEmpty || _uploadedMediaIds.isNotEmpty) &&
        !hasVideoWithoutCover &&
        !_isPublishing &&
        !_isUploading &&
        !_isPreparingVideo;
  }

  Widget _buildMediaSelector() {
    final hasImage = _selectedMedias.any((m) => m.mediaType == 1);
    final hasVideo = _selectedMedias.any((m) => m.mediaType == 2);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 添加图片按钮（最多4张，且无视频）
              if (!_isPreparingVideo &&
                  !hasVideo &&
                  _selectedMedias.where((m) => m.mediaType == 1).length < 4)
                _AddMediaButton(
                  icon: Icons.photo_library_outlined,
                  label: '图片',
                  onTap: () => _pickImage(),
                ),
              if (!_isPreparingVideo &&
                  !hasVideo &&
                  _selectedMedias.where((m) => m.mediaType == 1).length < 4)
                const SizedBox(width: 12),
              // 添加视频按钮（最多1个，且无图片）
              if (!_isPreparingVideo && !hasImage && !hasVideo)
                _AddMediaButton(
                  icon: Icons.videocam_outlined,
                  label: '视频（≤10s）',
                  onTap: () => _pickVideo(),
                ),
            ],
          ),

          if (_isPreparingVideo) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  '视频处理中，请稍候',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],

          // 已选媒体预览
          if (_selectedMedias.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedMedias.asMap().entries.map((entry) {
                final index = entry.key;
                final media = entry.value;
                return _MediaPreview(
                  media: media,
                  onRemove: () => _removeMedia(index),
                  onPreviewVideo: media.mediaType == 2
                      ? () => _previewVideo(index)
                      : null,
                  onEditCover: media.mediaType == 2
                      ? () => _editVideoCover(index)
                      : null,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_isPreparingVideo) return;
    try {
      final images = await _picker.pickMultiImage();
      if (images.isEmpty) return;
      final currentImages = _selectedMedias
          .where((m) => m.mediaType == 1)
          .length;
      final remain = 4 - currentImages;
      final toAdd = images.take(remain).toList();
      for (final img in toAdd) {
        final bytes = await img.readAsBytes();
        setState(() {
          _selectedMedias.add(
            _MediaItem(
              path: img.path,
              bytes: bytes,
              mediaType: 1,
              name: img.name,
            ),
          );
        });
      }
      if (images.length > remain) {
        _showToast('图片最多4张，已截断');
      }
    } catch (e) {
      _showToast('选择图片失败');
    }
  }

  Future<void> _pickVideo() async {
    if (_isPreparingVideo) return;

    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 10),
      );
      if (video == null) return;

      setState(() {
        _isPreparingVideo = true;
      });

      final preparedVideo = await VideoUploadPreprocessor.instance.prepareVideo(
        path: video.path,
        filename: video.name,
      );

      final duration = Duration(milliseconds: preparedVideo.durationMs);

      final cover = await _selectVideoCover(
        videoPath: video.path,
        duration: duration,
      );
      if (cover == null || cover.bytes.isEmpty) {
        _showToast('未选择封面，不能发布视频动态');
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedMedias.add(
          _MediaItem(
            path: video.path,
            bytes: preparedVideo.bytes,
            mediaType: 2,
            name: preparedVideo.filename,
            durationSeconds: preparedVideo.durationMs > 0
                ? (preparedVideo.durationMs / 1000).ceil()
                : null,
            coverBytes: cover.bytes,
            coverName: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
            coverTimeMs: cover.timeMs,
          ),
        );
      });
    } on VideoUploadPreprocessException catch (e) {
      _showToast(e.message);
    } catch (e) {
      _showToast('选择视频失败');
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingVideo = false;
        });
      }
    }
  }

  Future<_CoverSelection?> _selectVideoCover({
    required String videoPath,
    required Duration duration,
    int? initialTimeMs,
  }) async {
    return showDialog<_CoverSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VideoCoverPickerDialog(
        videoPath: videoPath,
        duration: duration,
        initialTimeMs: initialTimeMs,
      ),
    );
  }

  void _removeMedia(int index) {
    setState(() {
      _selectedMedias.removeAt(index);
    });
  }

  Future<void> _editVideoCover(int index) async {
    if (index < 0 || index >= _selectedMedias.length) return;
    final media = _selectedMedias[index];
    if (media.mediaType != 2) return;

    Duration duration;
    if (media.durationSeconds != null && media.durationSeconds! > 0) {
      duration = Duration(seconds: media.durationSeconds!);
    } else {
      final controller = VideoPlayerController.file(File(media.path));
      try {
        await controller.initialize();
        duration = controller.value.duration;
      } finally {
        await controller.dispose();
      }
    }

    final cover = await _selectVideoCover(
      videoPath: media.path,
      duration: duration,
      initialTimeMs: media.coverTimeMs,
    );
    if (cover == null || cover.bytes.isEmpty) return;

    setState(() {
      _selectedMedias[index] = media.copyWith(
        coverBytes: cover.bytes,
        coverName: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
        coverTimeMs: cover.timeMs,
      );
    });
  }

  void _previewVideo(int index) {
    if (index < 0 || index >= _selectedMedias.length) return;
    final media = _selectedMedias[index];
    if (media.mediaType != 2) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MomentVideoPreviewPage(videoUrl: media.path),
      ),
    );
  }

  Future<void> _publish() async {
    if (!_canPublish) return;

    setState(() {
      _isPublishing = true;
    });

    try {
      final content = _contentController.text.trim();

      // 1. 上传所有未上传的媒体
      for (final media in _selectedMedias) {
        if (_uploadedMediaIds.contains(media.tempId)) continue; // 已上传
        if (media.mediaType == 2 &&
            (media.coverBytes == null || media.coverBytes!.isEmpty)) {
          _showToast('视频必须选择封面后才能发布');
          return;
        }
        final result = await MomentService.instance.uploadMedia(
          bytes: media.bytes,
          filename: media.name,
          mediaType: media.mediaType,
          coverBytes: media.coverBytes,
          coverFilename: media.coverName,
          duration: media.durationSeconds,
        );
        if (result == null) {
          _showToast('上传失败');
          return;
        }
        _uploadedMediaIds.add(result['id'] as int);
      }

      // 2. 创建动态
      final moment = await MomentService.instance.createMoment(
        content: content,
        mediaIds: _uploadedMediaIds,
      );

      if (moment != null) {
        ref.read(momentFeedProvider.notifier).addMoment(moment);
        ref.read(myMomentsProvider.notifier).addMoment(moment);
        if (mounted) {
          Navigator.pop(context, moment);
          _showToast('发布成功');
        }
      } else {
        _showToast('发布失败');
      }
    } catch (e) {
      _showErrorToast(e);
    } finally {
      setState(() {
        _isPublishing = false;
      });
    }
  }

  void _confirmExit() {
    if (_contentController.text.isNotEmpty || _selectedMedias.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('退出发布'),
          content: const Text('确定要放弃已编辑的内容吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }
}

/// 媒体项（内存中）
class _MediaItem {
  final String path;
  final List<int> bytes;
  final int mediaType; // 1=图片, 2=视频
  final String name;
  final Uint8List? coverBytes;
  final String? coverName;
  final int? coverTimeMs;
  final int? durationSeconds;
  int? tempId = DateTime.now().microsecondsSinceEpoch;

  _MediaItem({
    required this.path,
    required this.bytes,
    required this.mediaType,
    required this.name,
    this.coverBytes,
    this.coverName,
    this.coverTimeMs,
    this.durationSeconds,
  });

  _MediaItem copyWith({
    Uint8List? coverBytes,
    String? coverName,
    int? coverTimeMs,
    int? durationSeconds,
  }) {
    return _MediaItem(
      path: path,
      bytes: bytes,
      mediaType: mediaType,
      name: name,
      coverBytes: coverBytes ?? this.coverBytes,
      coverName: coverName ?? this.coverName,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    )..tempId = tempId;
  }
}

/// 已选媒体预览
class _MediaPreview extends StatelessWidget {
  final _MediaItem media;
  final VoidCallback onRemove;
  final VoidCallback? onPreviewVideo;
  final VoidCallback? onEditCover;

  const _MediaPreview({
    required this.media,
    required this.onRemove,
    this.onPreviewVideo,
    this.onEditCover,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: media.mediaType == 2 ? onPreviewVideo : null,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: media.mediaType == 1
                        ? Image.memory(
                            media.bytes as dynamic,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _placeholder(),
                          )
                        : (media.coverBytes != null
                              ? Image.memory(
                                  media.coverBytes!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _placeholder(),
                                )
                              : _placeholder(label: '未选封面')),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                top: -4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
              if (media.mediaType == 2)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          if (media.mediaType == 2) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onEditCover,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  '编辑封面',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeholder({String label = ''}) {
    return Container(
      color: AppTheme.surfaceColor,
      child: Center(
        child: label.isEmpty
            ? const Icon(Icons.image, color: AppTheme.textHint, size: 28)
            : Text(
                label,
                style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
              ),
      ),
    );
  }
}

class _CoverSelection {
  final Uint8List bytes;
  final int timeMs;

  const _CoverSelection({required this.bytes, required this.timeMs});
}

class _VideoCoverPickerDialog extends StatefulWidget {
  final String videoPath;
  final Duration duration;
  final int? initialTimeMs;

  const _VideoCoverPickerDialog({
    required this.videoPath,
    required this.duration,
    this.initialTimeMs,
  });

  @override
  State<_VideoCoverPickerDialog> createState() =>
      _VideoCoverPickerDialogState();
}

class _VideoCoverPickerDialogState extends State<_VideoCoverPickerDialog> {
  int _currentMs = 500;
  Uint8List? _coverBytes;
  bool _loading = true;

  int get _maxMs {
    final ms = widget.duration.inMilliseconds;
    if (ms <= 0) return 1000;
    return ms;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTimeMs;
    if (initial != null) {
      _currentMs = initial.clamp(0, _maxMs);
    } else {
      _currentMs = _maxMs > 500 ? 500 : 0;
    }
    _loadThumbnail(_currentMs);
  }

  Future<void> _loadThumbnail(int timeMs) async {
    setState(() {
      _loading = true;
    });
    final bytes = await VideoThumbnail.thumbnailData(
      video: widget.videoPath,
      imageFormat: ImageFormat.JPEG,
      timeMs: timeMs,
      quality: 90,
    );
    if (!mounted) return;
    setState(() {
      _coverBytes = bytes;
      _loading = false;
    });
  }

  String _formatMs(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择视频封面'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: AppTheme.surfaceColor,
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (_coverBytes == null
                            ? const Center(child: Text('封面生成失败，请重试'))
                            : Image.memory(
                                _coverBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              )),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  _formatMs(_currentMs),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _currentMs.toDouble(),
                    min: 0,
                    max: _maxMs.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _currentMs = value.toInt();
                      });
                    },
                    onChangeEnd: (value) {
                      _loadThumbnail(value.toInt());
                    },
                  ),
                ),
                Text(
                  _formatMs(_maxMs),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '必须选择封面，未选择将不能发布',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: (_coverBytes == null || _loading)
              ? null
              : () {
                  Navigator.of(context).pop(
                    _CoverSelection(bytes: _coverBytes!, timeMs: _currentMs),
                  );
                },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 添加媒体按钮
class _AddMediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddMediaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
