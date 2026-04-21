import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 本地预览美颜相机 Widget
/// 包装 MtSurfaceCameraView PlatformView
class BeautyCameraView extends StatelessWidget {
  const BeautyCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    // 与参考项目一致：使用 AndroidView（Virtual Display）承载 CameraView。
    return const AndroidView(
      viewType: 'CameraView',
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
