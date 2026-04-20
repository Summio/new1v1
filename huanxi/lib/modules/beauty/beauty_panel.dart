import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import 'beauty_controller.dart';

/// 美颜面板 Widget
class BeautyPanel extends ConsumerStatefulWidget {
  const BeautyPanel({super.key});

  @override
  ConsumerState<BeautyPanel> createState() => _BeautyPanelState();
}

class _BeautyPanelState extends ConsumerState<BeautyPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(beautyControllerProvider);
    final controller = ref.read(beautyControllerProvider.notifier);

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动手柄
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Tab 标题
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.white54,
              indicatorColor: AppTheme.primaryColor,
              indicatorWeight: 2,
              tabs: const [
                Tab(text: '美颜'),
                Tab(text: '美型'),
                Tab(text: '滤镜'),
              ],
            ),
            // 全局重置按钮
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => controller.resetAll(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.refresh, color: Colors.white54, size: 16),
                        SizedBox(width: 4),
                        Text('恢复默认', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Tab 内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 美颜 Tab
                  _BeautyTab(state: state, controller: controller),
                  // 美型 Tab
                  _FaceShapeTab(state: state, controller: controller),
                  // 滤镜 Tab
                  _FilterTab(state: state, controller: controller),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 美颜 Tab
class _BeautyTab extends ConsumerWidget {
  final BeautyState state;
  final BeautyController controller;

  const _BeautyTab({required this.state, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // 总开关
        _SwitchRow(
          label: '美颜开关',
          value: state.isBeautyEnabled,
          onChanged: (_) => controller.toggleBeauty(),
        ),
        const SizedBox(height: 8),
        // 美白
        _SliderRow(
          label: '美白',
          value: state.whitening,
          onChanged: controller.setWhitening,
          enabled: state.isBeautyEnabled,
        ),
        // 磨皮
        _SliderRow(
          label: '磨皮',
          value: state.blurriness,
          onChanged: controller.setBlurriness,
          enabled: state.isBeautyEnabled,
        ),
        // 红润
        _SliderRow(
          label: '红润',
          value: state.rosiness,
          onChanged: controller.setRosiness,
          enabled: state.isBeautyEnabled,
        ),
        // 清晰
        _SliderRow(
          label: '清晰',
          value: state.clearness,
          onChanged: controller.setClearness,
          enabled: state.isBeautyEnabled,
        ),
        // 亮度
        _SliderRow(
          label: '亮度',
          value: state.brightness,
          onChanged: controller.setBrightness,
          enabled: state.isBeautyEnabled,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: state.isBeautyEnabled ? controller.resetBeauty : null,
            child: const Text('重置', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ],
    );
  }
}

/// 美型 Tab
class _FaceShapeTab extends ConsumerWidget {
  final BeautyState state;
  final BeautyController controller;

  const _FaceShapeTab({required this.state, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        _SwitchRow(
          label: '美型开关',
          value: state.isFaceShapeEnabled,
          onChanged: (_) => controller.toggleFaceShape(),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: '大眼',
          value: state.eyeEnlarging,
          onChanged: controller.setEyeEnlarging,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '圆眼',
          value: state.eyeRounding,
          onChanged: controller.setEyeRounding,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '瘦脸',
          value: state.cheekThinning,
          onChanged: controller.setCheekThinning,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: 'V脸',
          value: state.cheekV,
          onChanged: controller.setCheekV,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '窄脸',
          value: state.cheekNarrowing,
          onChanged: controller.setCheekNarrowing,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '下巴',
          value: state.chin,
          onChanged: controller.setChin,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '额头',
          value: state.forehead,
          onChanged: controller.setForehead,
          enabled: state.isFaceShapeEnabled,
        ),
        _SliderRow(
          label: '缩鼻',
          value: state.noseThinning,
          onChanged: controller.setNoseThinning,
          enabled: state.isFaceShapeEnabled,
        ),
        Center(
          child: TextButton(
            onPressed: state.isFaceShapeEnabled ? controller.resetFaceShape : null,
            child: const Text('重置', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ],
    );
  }
}

/// 滤镜 Tab
class _FilterTab extends ConsumerWidget {
  final BeautyState state;
  final BeautyController controller;

  const _FilterTab({required this.state, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: beautyFilters.length,
      itemBuilder: (context, index) {
        final filter = beautyFilters[index];
        final isSelected = state.currentFilter == filter.name;

        return GestureDetector(
          onTap: () => controller.setFilter(filter.name),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.3) : Colors.white12,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: AppTheme.primaryColor, width: 2) : null,
            ),
            alignment: Alignment.center,
            child: Text(
              filter.label,
              style: TextStyle(
                color: isSelected ? AppTheme.primaryColor : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}

/// 开关行
class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppTheme.primaryColor,
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.white : Colors.white54),
        ),
      ],
    );
  }
}

/// 滑条行
class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('$value', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.primaryColor,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: AppTheme.primaryColor.withValues(alpha: 0.2),
              trackHeight: 2,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              onChanged: enabled ? (v) => onChanged(v.round()) : null,
            ),
          ),
        ],
      ),
    );
  }
}
