import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';

/// 统一状态视图组件
/// 用于替换各处重复的 Loading/Error/Empty 状态 UI
class StatusView extends StatelessWidget {
  final StatusViewType type;
  final String? message;
  final VoidCallback? onRetry;

  const StatusView({
    super.key,
    required this.type,
    this.message,
    this.onRetry,
  });

  factory StatusView.loading({String? message}) {
    return StatusView(type: StatusViewType.loading, message: message);
  }

  factory StatusView.error({
    required String message,
    VoidCallback? onRetry,
  }) {
    return StatusView(
      type: StatusViewType.error,
      message: message,
      onRetry: onRetry,
    );
  }

  factory StatusView.empty({
    String? message,
    IconData icon = Icons.inbox_outlined,
  }) {
    return StatusView(
      type: StatusViewType.empty,
      message: message,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildContent(),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    switch (type) {
      case StatusViewType.loading:
        return [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 14,
              ),
            ),
          ],
        ];

      case StatusViewType.error:
        return [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppTheme.errorColor,
          ),
          const SizedBox(height: 16),
          Text(
            message ?? '加载失败',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ];

      case StatusViewType.empty:
        return [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: AppTheme.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message ?? '暂无数据',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 14,
            ),
          ),
        ];
    }
  }
}

enum StatusViewType {
  loading,
  error,
  empty,
}
