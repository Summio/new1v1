import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/moment_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../services/moment_service.dart';
import 'moment_card.dart';

/// 动态列表视图（支持下拉刷新 + 上拉加载更多）
class MomentListView extends ConsumerStatefulWidget {
  final List<Moment> moments;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final void Function(Moment moment)? onDelete; // 可选删除回调

  const MomentListView({
    super.key,
    required this.moments,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.onRefresh,
    required this.onLoadMore,
    this.onDelete,
  });

  @override
  ConsumerState<MomentListView> createState() => _MomentListViewState();
}

class _MomentListViewState extends ConsumerState<MomentListView> {
  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.moments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.error != null && widget.moments.isEmpty) {
      return _ErrorView(error: widget.error!, onRetry: widget.onRefresh);
    }

    if (widget.moments.isEmpty) {
      return _EmptyView();
    }

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: AppTheme.primaryColor,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 200) {
              widget.onLoadMore();
            }
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          itemCount: widget.moments.length + (widget.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == widget.moments.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final moment = widget.moments[index];
            return MomentCard(
              moment: moment,
              onDelete: widget.onDelete != null ? () => _confirmDelete(moment) : null,
            );
          },
        ),
      ),
    );
  }

  void _confirmDelete(Moment moment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定要删除这条动态吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete?.call(moment);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 错误视图
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态视图
class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dynamic_feed_outlined, size: 64, color: AppTheme.textHint),
          const SizedBox(height: 16),
          const Text(
            '暂无动态',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            '快去发布第一条动态吧',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
