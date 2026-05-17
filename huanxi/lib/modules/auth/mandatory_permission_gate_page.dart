import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/permissions/mandatory_permission_service.dart';

class MandatoryPermissionGatePage extends StatefulWidget {
  const MandatoryPermissionGatePage({super.key});

  @override
  State<MandatoryPermissionGatePage> createState() =>
      _MandatoryPermissionGatePageState();
}

class _MandatoryPermissionGatePageState extends State<MandatoryPermissionGatePage>
    with WidgetsBindingObserver {
  MandatoryPermissionState? _state;
  bool _loading = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkAndContinue(autoRequest: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkAndContinue());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkAndContinue({bool autoRequest = false}) async {
    setState(() {
      _loading = true;
    });
    final service = MandatoryPermissionService.instance;
    final next = autoRequest
        ? await service.ensureReadyForLoggedInUser()
        : await service.check();
    if (!mounted) return;
    setState(() {
      _state = next;
      _loading = false;
    });
    if (next.requiredGranted && mounted) {
      context.go(AppRoutes.index);
    }
  }

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
    });
    try {
      final next = await MandatoryPermissionService.instance
          .ensureReadyForLoggedInUser();
      if (!mounted) return;
      setState(() {
        _state = next;
      });
      if (next.requiredGranted) {
        context.go(AppRoutes.index);
      }
    } finally {
      if (mounted) {
        setState(() {
          _requesting = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing =
        _state?.requiredMissing ?? const <MandatoryPermissionCheck>[];
    final needsSettings = _state?.needsSettings ?? false;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '开启必要权限',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '欢喜需要相机和麦克风权限才能正常使用通话能力。通知和后台接听会尽量开启，未开启时不影响进入 App。',
                style: TextStyle(
                  height: 1.5,
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        itemCount: missing.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = missing[index];
                          return _PermissionItem(check: item);
                        },
                      ),
              ),
              FilledButton(
                onPressed: _requesting ? null : _requestPermissions,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _requesting
                      ? '正在检查...'
                      : needsSettings
                      ? '去系统设置开启'
                      : '立即授权',
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : () => _checkAndContinue(),
                child: const Text('我已开启，重新检查'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({required this.check});

  final MandatoryPermissionCheck check;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  check.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '未开启',
            style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
