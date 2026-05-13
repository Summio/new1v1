import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

/// 动态图片全屏预览页
/// 支持捏合缩放，点击任意位置关闭
class MomentImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  final List<String> imageUrls;
  final int initialIndex;

  const MomentImagePreviewPage({
    super.key,
    required this.imageUrl,
    this.imageUrls = const [],
    this.initialIndex = 0,
  });

  @override
  State<MomentImagePreviewPage> createState() => _MomentImagePreviewPageState();
}

class _MomentImagePreviewPageState extends State<MomentImagePreviewPage> {
  late final PageController _pageController;
  late final List<String> _images;
  late final int _initialPage;

  @override
  void initState() {
    super.initState();
    _images = _resolveImages();
    _initialPage = widget.initialIndex.clamp(0, _images.length - 1);
    _pageController = PageController(initialPage: _initialPage);
    // 隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _pageController.dispose();
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            key: const ValueKey('moment_image_preview_page_view'),
            controller: _pageController,
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return _ZoomableImagePage(imageUrl: _images[index], index: index);
            },
          ),
          if (_images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 28,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_images.length, (index) {
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        final page = _pageController.hasClients
                            ? (_pageController.page ?? _initialPage)
                            : _initialPage.toDouble();
                        final active = (page - index).abs() < 0.5;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 7 : 6,
                          height: active ? 7 : 6,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
            ),
          // 左上角关闭按钮（可选，备用关闭方式）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _resolveImages() {
    final source = widget.imageUrls.isEmpty
        ? [widget.imageUrl]
        : widget.imageUrls;
    final seen = <String>{};
    final out = <String>[];
    for (final item in source) {
      final url = item.trim();
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      out.add(url);
    }
    return out.isEmpty ? [widget.imageUrl] : out;
  }
}

class _ZoomableImagePage extends StatefulWidget {
  final String imageUrl;
  final int index;

  const _ZoomableImagePage({required this.imageUrl, required this.index});

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage> {
  static const double _minScale = 1.0;
  static const double _doubleTapScale = 2.5;
  static const double _scaleTolerance = 0.05;

  late final PhotoViewController _controller;
  late final PhotoViewScaleStateController _scaleStateController;
  late final StreamSubscription<PhotoViewControllerValue> _controllerStateSub;
  double? _initialResolvedScale;

  @override
  void initState() {
    super.initState();
    _controller = PhotoViewController();
    _scaleStateController = PhotoViewScaleStateController();
    _controllerStateSub = _controller.outputStateStream.listen(
      _captureInitialScale,
    );
  }

  @override
  void dispose() {
    _controllerStateSub.cancel();
    _scaleStateController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PhotoView(
      key: ValueKey('moment_image_preview_photo_${widget.index}'),
      imageProvider: _buildImageProvider(),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      controller: _controller,
      scaleStateController: _scaleStateController,
      minScale: PhotoViewComputedScale.contained,
      initialScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 4.0,
      scaleStateCycle: _scaleStateCycle,
      onTapUp: (context, details, value) => Navigator.of(context).pop(),
      loadingBuilder: (_, event) {
        return Center(
          child: CircularProgressIndicator(
            value: event?.expectedTotalBytes != null
                ? event!.cumulativeBytesLoaded / event.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
      gestureDetectorBehavior: HitTestBehavior.opaque,
    );
  }

  PhotoViewScaleState _scaleStateCycle(PhotoViewScaleState actual) {
    final isZoomedInState =
        actual == PhotoViewScaleState.zoomedIn ||
        _scaleStateController.scaleState == PhotoViewScaleState.zoomedIn;
    final currentScale = isZoomedInState ? _minScale : _currentRelativeScale();
    if (isZoomedInState || currentScale > _minScale + _scaleTolerance) {
      _controller.updateMultiple(
        position: Offset.zero,
        scale: _initialResolvedScale ?? _minScale,
      );
      return PhotoViewScaleState.initial;
    }

    _controller.updateMultiple(
      position: Offset.zero,
      scale: _resolvedInitialScale() * _doubleTapScale,
    );
    return PhotoViewScaleState.zoomedIn;
  }

  void _captureInitialScale(PhotoViewControllerValue value) {
    _initialResolvedScale ??= value.scale;
  }

  double _currentRelativeScale() {
    final baseScale = _resolvedInitialScale();
    final actualScale = _controller.scale ?? baseScale;
    return actualScale / baseScale;
  }

  double _resolvedInitialScale() {
    final initialScale = _initialResolvedScale;
    if (initialScale != null) return initialScale;

    final controllerScale = _controller.scale;
    if (controllerScale != null) {
      _initialResolvedScale = controllerScale;
      return controllerScale;
    }

    _initialResolvedScale = _minScale;
    return _minScale;
  }

  ImageProvider _buildImageProvider() {
    final localFile = File(widget.imageUrl);
    if (widget.imageUrl.startsWith('/uploads/') || localFile.existsSync()) {
      return FileImage(localFile);
    }
    return NetworkImage(widget.imageUrl);
  }

  Widget _errorPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
          SizedBox(height: 8),
          Text('图片加载失败', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
