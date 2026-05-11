import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_toast.dart';
import '../../services/user_home_service.dart';

Future<bool?> showUserMoreActions({
  required BuildContext context,
  required int targetUserId,
  required String targetName,
  required UserComplaintScene scene,
  required bool blockedByMe,
  required bool blockedMe,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: _UserMoreActionsSheet(
        targetUserId: targetUserId,
        targetName: targetName,
        scene: scene,
        blockedByMe: blockedByMe,
        blockedMe: blockedMe,
      ),
    ),
  );
}

class _UserMoreActionsSheet extends StatefulWidget {
  final int targetUserId;
  final String targetName;
  final UserComplaintScene scene;
  final bool blockedByMe;
  final bool blockedMe;

  const _UserMoreActionsSheet({
    required this.targetUserId,
    required this.targetName,
    required this.scene,
    required this.blockedByMe,
    required this.blockedMe,
  });

  @override
  State<_UserMoreActionsSheet> createState() => _UserMoreActionsSheetState();
}

class _UserMoreActionsSheetState extends State<_UserMoreActionsSheet> {
  bool _loading = false;

  Future<void> _toggleBlock() async {
    if (_loading) return;
    final blockedByMe = widget.blockedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(blockedByMe ? '确认解除拉黑' : '确认拉黑用户'),
        content: Text(
          blockedByMe
              ? '解除后，你们可以重新互相关注、聊天、通话和送礼。'
              : '拉黑后，你们将无法互相关注、聊天、通话和送礼。你可以在黑名单中解除拉黑。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: blockedByMe ? AppTheme.primaryColor : AppTheme.errorColor,
            ),
            child: Text(blockedByMe ? '解除拉黑' : '确认拉黑'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      if (blockedByMe) {
        await UserHomeService.instance.unblockUser(widget.targetUserId);
      } else {
        await UserHomeService.instance.blockUser(widget.targetUserId);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      AppToast.show(
        context,
        blockedByMe ? '已解除拉黑' : '已拉黑',
        backgroundColor: AppTheme.onlineGreen,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openComplaint() async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ComplaintDialog(
        targetUserId: widget.targetUserId,
        scene: widget.scene,
      ),
    );
    if (submitted == true && mounted) {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              widget.blockedByMe ? Icons.lock_open_rounded : Icons.block_rounded,
              color: widget.blockedByMe ? AppTheme.primaryColor : AppTheme.errorColor,
            ),
            title: Text(widget.blockedByMe ? '解除拉黑' : '拉黑'),
            subtitle: Text(widget.blockedByMe ? '恢复与 ${widget.targetName} 的互动' : '阻止双方继续互动'),
            enabled: !_loading && !widget.blockedMe,
            onTap: _toggleBlock,
          ),
          ListTile(
            leading: const Icon(Icons.report_gmailerrorred_rounded, color: AppTheme.errorColor),
            title: const Text('投诉'),
            subtitle: const Text('投诉用户'),
            enabled: !_loading,
            onTap: _openComplaint,
          ),
        ],
      ),
    );
  }
}

class _ComplaintDialog extends StatefulWidget {
  final int targetUserId;
  final UserComplaintScene scene;

  const _ComplaintDialog({required this.targetUserId, required this.scene});

  @override
  State<_ComplaintDialog> createState() => _ComplaintDialogState();
}

class _ComplaintDialogState extends State<_ComplaintDialog> {
  static const List<String> _reasons = [
    '骚扰辱骂',
    '色情低俗',
    '诈骗引流',
    '虚假资料',
    '其他',
  ];
  static const int _maxLength = 1000;

  final TextEditingController _contentController = TextEditingController();
  String _reason = _reasons.first;
  bool _loading = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      AppToast.show(context, '请填写投诉说明');
      return;
    }
    setState(() => _loading = true);
    try {
      await UserHomeService.instance.createComplaint(
        targetUserId: widget.targetUserId,
        scene: widget.scene,
        reason: _reason,
        content: content,
      );
      if (!mounted) return;
      AppToast.show(context, '投诉已提交', backgroundColor: AppTheme.onlineGreen);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('投诉用户'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: '投诉原因'),
              items: _reasons
                  .map((reason) => DropdownMenuItem(value: reason, child: Text(reason)))
                  .toList(),
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _reason = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              enabled: !_loading,
              maxLength: _maxLength,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: '补充说明',
                hintText: '请描述具体情况',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: Text(_loading ? '提交中' : '提交投诉'),
        ),
      ],
    );
  }
}
