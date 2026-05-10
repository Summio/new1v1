import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/theme/app_theme.dart';
import '../../app/providers/auth_provider.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/utils/capability_limit_guard.dart';
import '../../core/media/image_upload_preprocessor.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';

/// 真人认证状态
enum CertificationApplyStatus { none, pending, approved, rejected }

/// 真人认证状态数据
class CertificationApplyState {
  final CertificationApplyStatus status;
  final String? rejectReason;
  final String? facePhotoUrl;
  final bool isLoading;

  const CertificationApplyState({
    this.status = CertificationApplyStatus.none,
    this.rejectReason,
    this.facePhotoUrl,
    this.isLoading = false,
  });

  CertificationApplyState copyWith({
    CertificationApplyStatus? status,
    String? rejectReason,
    String? facePhotoUrl,
    bool? isLoading,
  }) {
    return CertificationApplyState(
      status: status ?? this.status,
      rejectReason: rejectReason ?? this.rejectReason,
      facePhotoUrl: facePhotoUrl ?? this.facePhotoUrl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 真人认证 Provider
class CertificationApplyNotifier
    extends StateNotifier<CertificationApplyState> {
  final DioClient _dio;

  CertificationApplyNotifier(this._dio)
    : super(const CertificationApplyState());

  /// 查询申请状态
  Future<void> fetchStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _dio.apiGet(ApiEndpoints.certificationApplyStatus);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = const CertificationApplyState();
        return;
      }

      final statusStr = respData['status'] as String? ?? 'none';
      state = CertificationApplyState(
        status: _parseStatus(statusStr),
        rejectReason: respData['reject_reason'] as String?,
        facePhotoUrl: (respData['face_photo_url'] as String?)?.trim(),
        isLoading: false,
      );
    } catch (_) {
      state = const CertificationApplyState();
    }
  }

  /// 上传正面照
  Future<String?> uploadFacePhoto({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final prepared = await ImageUploadPreprocessor.instance.prepareImage(
        bytes: bytes,
        filename: filename,
        scene: ImageUploadScene.avatar,
      );
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          prepared.bytes,
          filename: prepared.filename,
        ),
      });
      final resp = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.certificationApplyUploadFacePhoto,
        data: formData,
      );
      final body = resp.data ?? {};
      if ((body['code'] as int?) != 200) return null;
      final url = (body['data'] as Map<String, dynamic>?)?['url'] as String?;
      return (url == null || url.trim().isEmpty) ? null : url.trim();
    } on ApiException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// 提交申请
  Future<bool> apply({required String facePhotoUrl}) async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.certificationApply,
        data: {'face_photo_url': facePhotoUrl},
      );
      final code = data['code'] as int?;
      if (code == 200) {
        state = CertificationApplyState(
          status: CertificationApplyStatus.pending,
          rejectReason: null,
          facePhotoUrl: facePhotoUrl,
          isLoading: false,
        );
        return true;
      }
      state = state.copyWith(isLoading: false);
      return false;
    } on ApiException {
      state = state.copyWith(isLoading: false);
      rethrow;
    } on NetworkException {
      state = state.copyWith(isLoading: false);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  CertificationApplyStatus _parseStatus(String status) {
    switch (status) {
      case 'pending':
        return CertificationApplyStatus.pending;
      case 'approved':
        return CertificationApplyStatus.approved;
      case 'rejected':
        return CertificationApplyStatus.rejected;
      default:
        return CertificationApplyStatus.none;
    }
  }

  /// 重置为可申请状态（驳回后点击"重新申请"）
  void resetToForm() {
    state = const CertificationApplyState();
  }
}

/// 真人认证 Provider
final certificationApplyProvider =
    StateNotifierProvider<CertificationApplyNotifier, CertificationApplyState>((
      ref,
    ) {
      return CertificationApplyNotifier(DioClient.instance);
    });

/// 认证中心页
class CertificationCenterPage extends ConsumerStatefulWidget {
  const CertificationCenterPage({super.key});

  @override
  ConsumerState<CertificationCenterPage> createState() =>
      _CertificationCenterPageState();
}

class _CertificationCenterPageState
    extends ConsumerState<CertificationCenterPage> {
  static const String _exampleImageAsset =
      'assets/images/certification_apply_example.jpg';

  String? _localFacePhotoUrl;
  bool _uploading = false;
  int? _selectedPrice;
  bool _savingPrice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(appInitProvider.notifier).init();
      await ref.read(certificationApplyProvider.notifier).fetchStatus();
      if (!mounted) return;
      final authState = ref.read(authProvider);
      final initState = ref.read(appInitProvider);
      final message = certificationEntryRestrictionMessage(
        authState,
        initState,
      );
      if (message != null) {
        AppToast.show(context, message);
        context.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final applyState = ref.watch(certificationApplyProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('认证中心'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: applyState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('真人认证'),
                  const SizedBox(height: 10),
                  _buildPanel(child: _buildContent(applyState)),
                  const SizedBox(height: 16),
                  _buildSectionTitle('通话价格'),
                  const SizedBox(height: 10),
                  _buildPanel(child: _buildCallPriceContent()),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF2)),
      ),
      child: child,
    );
  }

  Widget _buildContent(CertificationApplyState state) {
    switch (state.status) {
      case CertificationApplyStatus.pending:
        return _buildPendingView(state);
      case CertificationApplyStatus.approved:
        return _buildApprovedView();
      case CertificationApplyStatus.rejected:
        return _buildRejectedView(state);
      case CertificationApplyStatus.none:
        return _buildApplyForm(state);
    }
  }

  Widget _buildPendingView(CertificationApplyState state) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.hourglass_empty,
            size: 80,
            color: AppTheme.secondaryColor,
          ),
          const SizedBox(height: 24),
          const Text(
            '申请已提交',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '请耐心等待审核，预计1-3个工作日',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          if ((state.facePhotoUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNetworkPhotoBox(state.facePhotoUrl!),
          ],
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => context.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            ),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Color(0xFF34C759)),
          const SizedBox(height: 24),
          const Text(
            '审核通过',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '您已通过真人认证',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => context.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedView(CertificationApplyState state) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cancel, size: 80, color: AppTheme.errorColor),
          const SizedBox(height: 24),
          const Text(
            '申请被拒绝',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          if ((state.rejectReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.rejectReason!.trim(),
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if ((state.facePhotoUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNetworkPhotoBox(state.facePhotoUrl!),
          ],
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _localFacePhotoUrl = null;
              });
              ref.read(certificationApplyProvider.notifier).resetToForm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            ),
            child: const Text('重新申请'),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyForm(CertificationApplyState state) {
    final facePhotoUrl = (_localFacePhotoUrl ?? state.facePhotoUrl ?? '')
        .trim();
    final canSubmit =
        facePhotoUrl.isNotEmpty && !_uploading && !state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCompactPhotoSection(facePhotoUrl: facePhotoUrl),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: canSubmit ? _handleSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD2D7DF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text(
              '提交审核',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallPriceContent() {
    final authState = ref.watch(authProvider);
    final initState = ref.watch(appInitProvider);
    final coinName = ref.watch(tokenNamesProvider).coinName;
    final isCertified = authState.isCertifiedUser;
    final configuredTiers = initState.certifiedCallPriceTiers;
    final paidTiers = configuredTiers.where((tier) => tier > 0).toList();
    final tiers = isCertified ? paidTiers : const [0];
    final currentPrice = isCertified ? authState.certifiedCallPrice : 0;
    final selected = tiers.isEmpty
        ? 0
        : tiers.contains(_selectedPrice)
        ? _selectedPrice!
        : (tiers.contains(currentPrice) ? currentPrice : tiers.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isCertified ? '选择每分钟通话价格' : '未通过真人认证时只能设置免费通话',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        if (tiers.isEmpty)
          const Text(
            '暂无可用通话价格，请联系平台配置',
            style: TextStyle(fontSize: 13, color: AppTheme.errorColor),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tiers.map((price) {
              final active = selected == price;
              return ChoiceChip(
                label: Text(_formatCallPrice(price, coinName)),
                selected: active,
                onSelected: isCertified
                    ? (_) {
                        setState(() {
                          _selectedPrice = price;
                        });
                      }
                    : null,
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                  color: active ? AppTheme.primaryColor : AppTheme.textPrimary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: isCertified && tiers.isNotEmpty && !_savingPrice
                ? () => _saveCallPrice(selected)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD2D7DF),
            ),
            child: Text(_savingPrice ? '保存中...' : '保存通话价格'),
          ),
        ),
      ],
    );
  }

  Future<void> _saveCallPrice(int price) async {
    setState(() {
      _savingPrice = true;
    });
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.certifiedCallPriceUpdate,
        data: {'price': price},
      );
      if ((data['code'] as int?) != 200) {
        throw ApiException(
          code: data['code'] as int? ?? -1,
          message: data['msg'] as String? ?? '保存失败',
        );
      }
      await ref.read(authProvider.notifier).fetchUserInfo();
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(
          content: Text('通话价格已保存'),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (mounted) AppToast.error(context, '保存失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _savingPrice = false;
        });
      }
    }
  }

  String _formatCallPrice(int price, String coinName) {
    if (price <= 0) return '免费';
    return '$price$coinName/分钟';
  }

  Widget _buildCompactPhotoSection({required String facePhotoUrl}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '正面照上传',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '仅支持调用摄像头自拍，不支持相册上传。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '示例',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE4E9F2)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            _exampleImageAsset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stackTrace) {
                              return const Center(
                                child: Text(
                                  '示例图生成中',
                                  style: TextStyle(
                                    color: Color(0xFF6B7380),
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '你的照片',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: facePhotoUrl.isEmpty
                          ? Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F7FB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE4E9F2),
                                ),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt_outlined,
                                    size: 34,
                                    color: Color(0xFF8F98AA),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '尚未拍摄',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                facePhotoUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _handleCapture,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_uploading ? '上传中...' : '拍摄正面照'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkPhotoBox(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(url, width: 180, height: 220, fit: BoxFit.cover),
    );
  }

  Future<void> _handleCapture() async {
    try {
      final captured = await Navigator.of(context).push<_CapturedPhoto>(
        MaterialPageRoute(
          builder: (_) => const _FrontCameraCapturePage(),
          fullscreenDialog: true,
        ),
      );
      if (captured == null) return;

      if (!mounted) return;
      setState(() {
        _uploading = true;
      });

      final url = await ref
          .read(certificationApplyProvider.notifier)
          .uploadFacePhoto(bytes: captured.bytes, filename: captured.filename);
      if (url == null || url.isEmpty) {
        throw const ApiException(code: -1, message: '上传失败，请重试');
      }

      if (!mounted) return;
      setState(() {
        _localFacePhotoUrl = url;
      });
      AppToast.showSnackBar(
        context,
        const SnackBar(
          content: Text('正面照上传成功'),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, '拍照或上传失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<void> _handleSubmit() async {
    final facePhotoUrl = (_localFacePhotoUrl ?? '').trim();
    if (facePhotoUrl.isEmpty) {
      AppToast.error(context, '请先拍摄并上传正面照');
      return;
    }

    final success = await ref
        .read(certificationApplyProvider.notifier)
        .apply(facePhotoUrl: facePhotoUrl)
        .catchError((Object error) {
          if (mounted) AppToast.error(context, error);
          return false;
        });

    if (success && mounted) {
      AppToast.showSnackBar(
        context,
        const SnackBar(
          content: Text('申请已提交'),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    }
  }
}

class _CapturedPhoto {
  final Uint8List bytes;
  final String filename;

  const _CapturedPhoto({required this.bytes, required this.filename});
}

class _CameraInitException implements Exception {
  final String message;
  final bool openSettings;

  const _CameraInitException(this.message, {this.openSettings = false});
}

class _FrontCameraCapturePage extends StatefulWidget {
  const _FrontCameraCapturePage();

  @override
  State<_FrontCameraCapturePage> createState() =>
      _FrontCameraCapturePageState();
}

class _FrontCameraCapturePageState extends State<_FrontCameraCapturePage> {
  CameraController? _controller;
  bool _capturing = false;
  bool _initializing = true;
  String? _errorText;
  bool _shouldOpenSettings = false;

  @override
  void initState() {
    super.initState();
    _initFrontCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initFrontCamera() async {
    try {
      await _controller?.dispose();
      _controller = null;

      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (permission.isPermanentlyDenied || permission.isRestricted) {
          throw const _CameraInitException(
            '相机权限被禁用，请到系统设置中开启后重试',
            openSettings: true,
          );
        }
        throw const _CameraInitException('未获取相机权限，请允许后重试');
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const _CameraInitException('当前设备未检测到可用摄像头');
      }

      CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      if (frontCamera == null) {
        throw const _CameraInitException('当前设备不支持前置摄像头自拍');
      }

      final controller = await _buildControllerWithFallback(frontCamera);
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
        _errorText = null;
        _shouldOpenSettings = false;
      });
    } on _CameraInitException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorText = e.message;
        _shouldOpenSettings = e.openSettings;
      });
    } on CameraException catch (e) {
      final normalized = _normalizeCameraException(e);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _shouldOpenSettings = normalized.openSettings;
        _errorText = normalized.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorText = '前置摄像头启动失败：${e.runtimeType}';
        _shouldOpenSettings = false;
      });
    }
  }

  Future<CameraController> _buildControllerWithFallback(
    CameraDescription camera,
  ) async {
    final presets = <ResolutionPreset>[
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];
    CameraException? lastError;

    for (final preset in presets) {
      final controller = CameraController(
        camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await controller.initialize();
        return controller;
      } on CameraException catch (e) {
        lastError = e;
        await controller.dispose();
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const _CameraInitException('前置摄像头初始化失败');
  }

  _CameraInitException _normalizeCameraException(CameraException e) {
    final code = e.code.toLowerCase();
    final desc = (e.description ?? '').trim();

    if (code.contains('accessdenied') || code.contains('permission')) {
      return const _CameraInitException(
        '相机权限不足，请在系统设置中开启后重试',
        openSettings: true,
      );
    }
    if (code.contains('already') || code.contains('inuse')) {
      return const _CameraInitException('摄像头正在被占用，请关闭其他相机应用后重试');
    }
    if (desc.isNotEmpty) {
      return _CameraInitException(desc);
    }
    return _CameraInitException('前置摄像头启动失败（${e.code}）');
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null) return;
    try {
      setState(() {
        _capturing = true;
      });
      final picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(
        _CapturedPhoto(
          bytes: bytes,
          filename:
              'certification_face_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
      });
      AppToast.error(context, '拍照失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('前置摄像头自拍'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
          ? _buildErrorView()
          : controller == null
          ? _buildErrorView()
          : _buildCameraView(controller),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorText ?? '摄像头暂不可用',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _errorText = null;
                  _shouldOpenSettings = false;
                });
                _initFrontCamera();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: const Text('重试'),
            ),
            if (_shouldOpenSettings) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: openAppSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                child: const Text('去设置开启权限'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(CameraController controller) {
    final previewSize = controller.value.previewSize;

    return Stack(
      children: [
        Positioned.fill(
          child: previewSize == null
              ? CameraPreview(controller)
              : FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    // Camera plugin returns preview size in landscape space.
                    width: previewSize.height,
                    height: previewSize.width,
                    child: CameraPreview(controller),
                  ),
                ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: GestureDetector(
              onTap: _capturing ? null : _capture,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white70, width: 3),
                ),
                child: _capturing
                    ? const Padding(
                        padding: EdgeInsets.all(22),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
