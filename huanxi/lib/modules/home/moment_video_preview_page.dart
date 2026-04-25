import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/utils/media_url.dart';

/// 动态视频全屏预览页
class MomentVideoPreviewPage extends StatefulWidget {
  final String videoUrl;

  const MomentVideoPreviewPage({super.key, required this.videoUrl});

  @override
  State<MomentVideoPreviewPage> createState() => _MomentVideoPreviewPageState();
}

class _MomentVideoPreviewPageState extends State<MomentVideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _isReady = false;
  bool _hasError = false;
  bool _showControls = true;
  String _errorText = '视频加载失败';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = _buildVideoController(widget.videoUrl);

      await controller.initialize();
      await controller.play();
      controller.setLooping(true);
      controller.addListener(_onControllerUpdated);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isReady = true;
        _hasError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorText = '视频初始化失败，请检查文件路径或网络地址';
      });
    }
  }

  VideoPlayerController _buildVideoController(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('Empty video url');
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      return VideoPlayerController.networkUrl(Uri.parse(input));
    }

    if (input.startsWith('file://')) {
      final localPath = Uri.parse(input).toFilePath();
      return VideoPlayerController.file(File(localPath));
    }

    final localFile = File(input);
    if (localFile.existsSync()) {
      return VideoPlayerController.file(localFile);
    }

    final resolvedUrl = toAbsoluteMediaUrl(input);
    if (resolvedUrl.isEmpty) {
      throw const FormatException('Empty resolved video url');
    }
    if (resolvedUrl.startsWith('http://') ||
        resolvedUrl.startsWith('https://')) {
      return VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
    }
    return VideoPlayerController.file(File(resolvedUrl));
  }

  void _onControllerUpdated() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!controller.value.hasError) return;
    setState(() {
      _hasError = true;
      _errorText = controller.value.errorDescription?.trim().isNotEmpty == true
          ? controller.value.errorDescription!.trim()
          : '视频播放失败';
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdated);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !_isReady) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_hasError)
              _buildErrorView()
            else if (!_isReady || controller == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio > 0
                      ? controller.value.aspectRatio
                      : 9 / 16,
                  child: VideoPlayer(controller),
                ),
              ),
            if (_showControls) ...[
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (_isReady && controller != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white.withValues(
                                alpha: 0.35,
                              ),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 56),
          const SizedBox(height: 10),
          Text(
            _errorText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
