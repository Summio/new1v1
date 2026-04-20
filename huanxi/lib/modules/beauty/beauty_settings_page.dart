import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import 'beauty_camera_view.dart';
import 'beauty_panel.dart';

class BeautySettingsPage extends ConsumerWidget {
  const BeautySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 顶部导航栏
          SafeArea(
            bottom: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '美颜设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // 占位，保持标题居中
                ],
              ),
            ),
          ),
          // 相机预览区域 (flex: 6)
          Expanded(
            flex: 6,
            child: Container(
              color: Colors.black,
              child: const Center(
                child: BeautyCameraView(),
              ),
            ),
          ),
          // 美颜面板区域 (flex: 4)
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const BeautyPanel(),
            ),
          ),
        ],
      ),
    );
  }
}