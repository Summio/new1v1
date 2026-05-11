import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../services/teen_mode_service.dart';

class TeenModeSetupPage extends StatefulWidget {
  const TeenModeSetupPage({super.key});

  @override
  State<TeenModeSetupPage> createState() => _TeenModeSetupPageState();
}

class _TeenModeSetupPageState extends State<TeenModeSetupPage> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    final confirmPin = _confirmController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage('请输入4位数字密码');
      return;
    }
    if (pin != confirmPin) {
      _showMessage('两次密码不一致');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await TeenModeService.instance.enable(pin);
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('青少年模式已开启')),
      );
      context.pop(true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    AppToast.showSnackBar(
      context,
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('设置青少年模式'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '设置4位数字密码',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '开启后将进入青少年模式，输入正确密码后会解除并关闭该模式。',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _PinField(
            controller: _pinController,
            label: '密码',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _PinField(
            controller: _confirmController,
            label: '确认密码',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(_isSubmitting ? '开启中...' : '开启青少年模式'),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _PinField({
    required this.controller,
    required this.label,
    required this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        filled: true,
        fillColor: AppTheme.surfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      maxLength: 4,
    );
  }
}
