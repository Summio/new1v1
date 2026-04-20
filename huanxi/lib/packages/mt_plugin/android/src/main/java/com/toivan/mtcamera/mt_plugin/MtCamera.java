package com.toivan.mtcamera.mt_plugin;

import android.content.Context;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.Camera;
import android.os.Build;
import android.util.Log;
import android.view.Surface;
import android.view.WindowManager;
import java.io.IOException;
import java.util.List;

@SuppressWarnings("deprecation")
public class MtCamera {

    private final String TAG = "MtCamera";

    private Camera camera;
    private Context context;

    public MtCamera(Context context) {
        this.context = context;
    }

    public boolean openCamera(int cameraId, int width, int height) {
        final boolean xiaomiLike = isXiaomiLikeDevice();
        // Xiaomi/Redmi/POCO 机型在 setParameters 路径上存在厂商 companion hook 崩溃风险：
        // 日志可见 CameraEventHandler.onSetParameters/onStartPreview NPE。
        // 先跳过参数配置，使用系统默认参数起相机，避免触发该崩溃链路。
        if (xiaomiLike) {
            Log.w(TAG, "openCamera Xiaomi-like: skip setParameters path first");
            if (openCameraInternal(cameraId, width, height, false)) {
                return true;
            }
            releaseCamera();
        }

        // 先尝试按目标分辨率配置；若厂商兼容层异常，再回退为默认参数重开。
        if (openCameraInternal(cameraId, width, height, true)) {
            return true;
        }
        releaseCamera();
        Log.w(TAG, "openCamera fallback: reopen with default parameters");
        return openCameraInternal(cameraId, width, height, false);
    }

    private boolean isXiaomiLikeDevice() {
        final String manufacturer = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.toLowerCase();
        final String brand = Build.BRAND == null ? "" : Build.BRAND.toLowerCase();
        return manufacturer.contains("xiaomi")
            || brand.contains("xiaomi")
            || brand.contains("redmi")
            || brand.contains("poco");
    }

    private boolean openCameraInternal(int cameraId, int width, int height, boolean configureParameters) {
        try {
            camera = Camera.open(cameraId);
            if (camera == null) {
                Log.e(TAG, "MtCamera openCamera failed: camera is null");
                return false;
            }

            if (configureParameters) {
                final Camera.Parameters parameters = camera.getParameters();
                if (parameters == null) {
                    Log.e(TAG, "MtCamera getParameters returned null");
                    return false;
                }

                if (isPreviewFormatSupported(parameters, ImageFormat.NV21)) {
                    parameters.setPreviewFormat(ImageFormat.NV21);
                }

                final Camera.Size matchedSize = findMatchedPreviewSize(parameters, width, height);
                if (matchedSize != null) {
                    parameters.setPreviewSize(matchedSize.width, matchedSize.height);
                } else {
                    Log.w(TAG, "Requested preview size not supported: " + width + "x" + height);
                }

                camera.setParameters(parameters);
            }

            setCameraDisplayOrientation(context, cameraId, camera);
            Log.i(TAG, "MtCamera open camera: " + cameraId);
            return true;
        } catch (RuntimeException e) {
            Log.e(TAG, "MtCamera openCamera error: " + e.getMessage());
            releaseCamera();
            return false;
        }
    }

    private boolean isPreviewFormatSupported(Camera.Parameters parameters, int format) {
        try {
            final List<Integer> formats = parameters.getSupportedPreviewFormats();
            return formats != null && formats.contains(format);
        } catch (RuntimeException e) {
            Log.w(TAG, "getSupportedPreviewFormats failed: " + e.getMessage());
            return false;
        }
    }

    private Camera.Size findMatchedPreviewSize(Camera.Parameters parameters, int width, int height) {
        try {
            final List<Camera.Size> sizes = parameters.getSupportedPreviewSizes();
            if (sizes == null || sizes.isEmpty()) {
                return null;
            }
            Camera.Size best = null;
            for (Camera.Size size : sizes) {
                if (size.width == width && size.height == height) {
                    return size;
                }
                if (best == null) {
                    best = size;
                }
            }
            return best;
        } catch (RuntimeException e) {
            Log.w(TAG, "getSupportedPreviewSizes failed: " + e.getMessage());
            return null;
        }
    }

    public boolean setPreviewSurface(SurfaceTexture previewSurface) {
        if (camera == null) {
            Log.w(TAG, "setPreviewSurface skipped: camera is null");
            return false;
        }
        try {
            camera.setPreviewTexture(previewSurface);
            return true;
        } catch (IOException e) {
            Log.e(TAG, e.getMessage());
            return false;
        } catch (RuntimeException e) {
            Log.e(TAG, "setPreviewSurface runtime error: " + e.getMessage());
            return false;
        }
    }

    public boolean startPreview() {
        if (camera == null) {
            Log.w(TAG, "startPreview skipped: camera is null");
            return false;
        }
        try {
            camera.startPreview();
            Log.i(TAG, "MtCamera startPreview");
            return true;
        } catch (RuntimeException e) {
            Log.e(TAG, "startPreview runtime error: " + e.getMessage());
            return false;
        }
    }

    public void stopPreview() {
        camera.stopPreview();
        Log.i(TAG, "MtCamera stopPreview");
    }

    public void releaseCamera() {
        if (camera != null) {
            camera.setPreviewCallback(null);
            try {
                camera.stopPreview();
            } catch (RuntimeException e) {
                Log.w(TAG, "stopPreview ignored in release: " + e.getMessage());
            }
            camera.release();
            camera = null;
        }
        Log.i(TAG, "MtCamera releaseCamera");
    }

    private void setCameraDisplayOrientation(Context context, int cameraId, Camera camera) {
        Camera.CameraInfo info = new Camera.CameraInfo();
        Camera.getCameraInfo(cameraId, info);
        WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        if (windowManager == null) {
            Log.e(TAG, "WindowManager is null");
            return;
        }
        int rotation = windowManager.getDefaultDisplay().getRotation();
        int degrees = 0;
        switch (rotation) {
            case Surface.ROTATION_0: degrees = 0; break;
            case Surface.ROTATION_90: degrees = 90; break;
            case Surface.ROTATION_180: degrees = 180; break;
            case Surface.ROTATION_270: degrees = 270; break;
        }
        int result;
        if (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
            result = (info.orientation + degrees) % 360;
            result = (360 - result) % 360;
        } else {
            result = (info.orientation - degrees + 360) % 360;
        }
        camera.setDisplayOrientation(result);
    }
}
