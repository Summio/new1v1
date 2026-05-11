import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_toast.dart';
import '../../services/user_home_service.dart';

class ComplaintPage extends StatefulWidget {
  final int? targetUserId;
  final String? targetName;
  final UserComplaintScene? scene;

  const ComplaintPage({
    super.key,
    required this.targetUserId,
    required this.targetName,
    required this.scene,
  });

  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  static const List<String> _reasons = ['骚扰辱骂', '色情低俗', '诈骗引流', '虚假资料', '其他'];
  static const int _maxLength = 1000;

  final TextEditingController _contentController = TextEditingController();
  String _reason = _reasons.first;
  bool _loading = false;

  bool get _hasValidParams =>
      widget.targetUserId != null &&
      widget.targetUserId! > 0 &&
      widget.scene != null;

  String get _displayName {
    final name = widget.targetName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return '用户${widget.targetUserId ?? ''}';
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_hasValidParams || _loading) return;
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      AppToast.show(context, '请填写投诉说明');
      return;
    }

    setState(() => _loading = true);
    try {
      await UserHomeService.instance.createComplaint(
        targetUserId: widget.targetUserId!,
        scene: widget.scene!,
        reason: _reason,
        content: content,
      );
      if (!mounted) return;
      AppToast.show(context, '投诉已提交', backgroundColor: AppTheme.onlineGreen);
      context.pop();
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final contentLength = _contentController.text.length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('投诉用户'),
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
      ),
      body: _hasValidParams
          ? GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TargetUserPanel(
                      targetUserId: widget.targetUserId!,
                      targetName: _displayName,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _reason,
                            decoration: const InputDecoration(
                              labelText: '投诉原因',
                            ),
                            items: _reasons
                                .map(
                                  (reason) => DropdownMenuItem(
                                    value: reason,
                                    child: Text(reason),
                                  ),
                                )
                                .toList(),
                            onChanged: _loading
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() => _reason = value);
                                  },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _contentController,
                            enabled: !_loading,
                            maxLength: 1000,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            maxLines: 8,
                            minLines: 5,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: '补充说明',
                              hintText: '请描述具体情况',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$contentLength/$_maxLength',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                '提交投诉',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '投诉参数无效，请返回重试',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

class _TargetUserPanel extends StatelessWidget {
  final int targetUserId;
  final String targetName;

  const _TargetUserPanel({
    required this.targetUserId,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: '被投诉人ID', value: targetUserId.toString()),
          const SizedBox(height: 10),
          _InfoRow(label: '被投诉人昵称', value: targetName),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
