import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../services/teen_mode_service.dart';

class TeenModeVerifyPage extends StatefulWidget {
  const TeenModeVerifyPage({super.key});

  @override
  State<TeenModeVerifyPage> createState() => _TeenModeVerifyPageState();
}

class _TeenModeVerifyPageState extends State<TeenModeVerifyPage> {
  final TextEditingController _pinController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage('请输入4位数字密码');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final verified = await TeenModeService.instance.verifyAndDisable(pin);
      if (!mounted) return;
      if (!verified) {
        _showMessage('密码错误');
        return;
      }
      _showMessage('密码验证成功');
      context.go(AppRoutes.index);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    AppToast.showSnackBar(context, SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppTheme.surfaceColor,
          centerTitle: true,
          title: const Text('青少年模式'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 20),
                const Text(
                  '输入密码解除青少年模式',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '验证成功后将立即关闭青少年模式。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '4位数字密码',
                    counterText: '',
                    filled: true,
                    fillColor: AppTheme.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLength: 4,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(_isSubmitting ? '验证中...' : '验证并关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
