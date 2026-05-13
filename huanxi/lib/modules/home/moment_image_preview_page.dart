import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _MomentImagePreviewPageState extends State<MomentImagePreviewPage>
    with TickerProviderStateMixin {
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
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              key: const ValueKey('moment_image_preview_page_view'),
              controller: _pageController,
              itemCount: _images.length,
              itemBuilder: (context, index) {
                return _ZoomableImagePage(
                  imageUrl: _images[index],
                  index: index,
                );
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

class _ZoomableImagePageState extends State<_ZoomableImagePage>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1.0;
  static const double _maxScale = 4.0;
  static const double _doubleTapScale = 2.5;

  late final TransformationController _transformationController;
  AnimationController? _animationController;
  Animation<Matrix4>? _matrixAnimation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: () => _handleDoubleTap(screenSize),
      child: InteractiveViewer(
        minScale: _minScale,
        maxScale: _maxScale,
        boundaryMargin: EdgeInsets.zero,
        transformationController: _transformationController,
        onInteractionEnd: (_) => _snapToBounds(screenSize),
        child: SizedBox(
          width: screenSize.width,
          height: screenSize.height,
          child: _buildImage(
            width: screenSize.width,
            height: screenSize.height,
          ),
        ),
      ),
    );
  }

  void _handleDoubleTap(Size viewport) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }

    final position =
        _doubleTapDetails?.localPosition ??
        Offset(viewport.width / 2, viewport.height / 2);
    final target = _buildMatrix(
      scale: _doubleTapScale,
      tx: -position.dx * (_doubleTapScale - 1),
      ty: -position.dy * (_doubleTapScale - 1),
    );

    _animateTo(_clampMatrix(target, viewport));
  }

  void _snapToBounds(Size viewport) {
    final clamped = _clampMatrix(_transformationController.value, viewport);
    if (!_isSameMatrix(_transformationController.value, clamped)) {
      _animateTo(clamped);
    }
  }

  void _animateTo(Matrix4 target) {
    _animationController?.dispose();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _matrixAnimation =
        Matrix4Tween(
            begin: _transformationController.value,
            end: target,
          ).animate(
            CurvedAnimation(
              parent: _animationController!,
              curve: Curves.easeOutCubic,
            ),
          )
          ..addListener(() {
            _transformationController.value = _matrixAnimation!.value;
          });
    _animationController!.forward();
  }

  Matrix4 _clampMatrix(Matrix4 matrix, Size viewport) {
    var scale = matrix.getMaxScaleOnAxis();
    scale = scale.clamp(_minScale, _maxScale);

    if (scale <= _minScale) {
      return Matrix4.identity();
    }

    final tx = matrix.storage[12];
    final ty = matrix.storage[13];

    final minTx = viewport.width - viewport.width * scale;
    final minTy = viewport.height - viewport.height * scale;

    final clampedTx = tx.clamp(minTx, 0.0);
    final clampedTy = ty.clamp(minTy, 0.0);

    return _buildMatrix(
      scale: scale,
      tx: clampedTx.toDouble(),
      ty: clampedTy.toDouble(),
    );
  }

  Matrix4 _buildMatrix({
    required double scale,
    required double tx,
    required double ty,
  }) {
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(tx, ty, 0);
  }

  bool _isSameMatrix(Matrix4 a, Matrix4 b) {
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > 0.001) {
        return false;
      }
    }
    return true;
  }

  Widget _buildImage({required double width, required double height}) {
    if (widget.imageUrl.startsWith('/uploads/')) {
      return Image.file(
        File(widget.imageUrl),
        key: ValueKey('moment_image_preview_image_${widget.index}'),
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
      );
    }
    return Image.network(
      widget.imageUrl,
      key: ValueKey('moment_image_preview_image_${widget.index}'),
      width: width,
      height: height,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _errorPlaceholder(),
    );
  }

  Widget _errorPlaceholder() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
        SizedBox(height: 8),
        Text('图片加载失败', style: TextStyle(color: Colors.white54)),
      ],
    );
  }
}
