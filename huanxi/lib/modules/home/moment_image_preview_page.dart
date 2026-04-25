import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 动态图片全屏预览页
/// 支持捏合缩放，点击任意位置关闭
class MomentImagePreviewPage extends StatefulWidget {
  final String imageUrl;

  const MomentImagePreviewPage({super.key, required this.imageUrl});

  @override
  State<MomentImagePreviewPage> createState() => _MomentImagePreviewPageState();
}

class _MomentImagePreviewPageState extends State<MomentImagePreviewPage> {
  @override
  void initState() {
    super.initState();
    // 隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
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
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: _buildImage(),
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

  Widget _buildImage() {
    if (widget.imageUrl.startsWith('/uploads/')) {
      return Image.file(
        File(widget.imageUrl),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _errorPlaceholder(),
      );
    }
    return Image.network(
      widget.imageUrl,
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
      errorBuilder: (_, __, ___) => _errorPlaceholder(),
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