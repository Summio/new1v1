import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers/wallet_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/media_url.dart';

class WithdrawAccountPage extends ConsumerStatefulWidget {
  final WithdrawAccount? initialAccount;

  const WithdrawAccountPage({super.key, this.initialAccount});

  @override
  ConsumerState<WithdrawAccountPage> createState() =>
      _WithdrawAccountPageState();
}

class _WithdrawAccountPageState extends ConsumerState<WithdrawAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _realNameController = TextEditingController();
  final _accountNoController = TextEditingController();
  final _picker = ImagePicker();
  String _paymentQrCode = '';
  bool _isUploading = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final account = widget.initialAccount;
    _realNameController.text = account?.realName ?? '';
    _accountNoController.text = account?.accountNo ?? '';
    _paymentQrCode = account?.paymentQrCode ?? '';
  }

  @override
  void dispose() {
    _realNameController.dispose();
    _accountNoController.dispose();
    super.dispose();
  }

  Future<void> _pickQrCode() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _isUploading = true);
    final bytes = await picked.readAsBytes();
    final url = await ref
        .read(walletProvider.notifier)
        .uploadWithdrawQrCode(bytes: bytes, filename: picked.name);
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (url == null) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('收款码上传失败')));
      return;
    }
    setState(() => _paymentQrCode = url);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paymentQrCode.isEmpty) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('请上传支付宝收款码')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final account = await ref
        .read(walletProvider.notifier)
        .saveWithdrawAccount(
          realName: _realNameController.text.trim(),
          accountNo: _accountNoController.text.trim(),
          paymentQrCode: _paymentQrCode,
        );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (account == null) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('提现账户提交失败')));
      return;
    }
    context.pop(account);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('提现账户'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '真实姓名',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _realNameController,
                decoration: _inputDecoration('请输入真实姓名'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入真实姓名' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                '支付宝账号',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _accountNoController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('请输入支付宝账号'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入支付宝账号' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                '收款码',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _isUploading ? null : _pickQrCode,
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E5EA)),
                  ),
                  child: _isUploading
                      ? const Center(child: CircularProgressIndicator())
                      : _paymentQrCode.isEmpty
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 44,
                              color: AppTheme.textHint,
                            ),
                            SizedBox(height: 8),
                            Text(
                              '上传支付宝收款码',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: toAbsoluteMediaUrl(_paymentQrCode),
                            fit: BoxFit.contain,
                            errorWidget: (context, url, error) =>
                                const Center(child: Text('收款码预览失败')),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        color: AppTheme.surfaceColor,
        child: SizedBox(
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ElevatedButton(
              onPressed: (_isUploading || _isSubmitting) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '提交审核',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: AppTheme.surfaceColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
