package com.toivan.mtcamera.mt_plugin.view

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.Camera
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.widget.FrameLayout
import com.toivan.mtcamera.mt_plugin.MtCamera
import com.toivan.mtcamera.mt_plugin.util.MtSharedPreferences
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import com.nimo.facebeauty.FBEffect
import com.nimo.facebeauty.model.FBRotationEnum
import com.nimo.facebeauty.FBPreviewRenderer
import com.nimo.facebeauty.egl.FBGLUtils
import android.opengl.GLES20
import com.toivan.mtcamera.mt_plugin.MtPlugin
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val TAG = "MtCameraVie"

@Suppress("DEPRECATION", "unused")
class MtSurfaceCameraView(mContext: Context) : AutoFitGlSurfaceView(mContext), GLSurfaceView.Renderer {

    private val uiHandler = Handler(Looper.getMainLooper())
    private var camera: MtCamera
    private var surfaceTexture: SurfaceTexture? = null
    private var oesTextureId: Int = 0
    private var isFrontCamera = true
    private var isCameraSwitched = false
    private var mtRotation: FBRotationEnum? = null
    private var previewRenderer: FBPreviewRenderer? = null
    private var isRenderInit = false
    // 默认优先高清，失败时在候选列表中自动降级。
    private var imageWidth = 1280
    private var imageHeight: Int = 720
    private var surfaceWidth = 0
    private var surfaceHeight: Int = 0
    private var surfaceWidthF = 0f
    private var surfaceHeightF = 0f
    private var textureId = 2
    private var lastPushTsMs: Long = 0
    private val pushIntervalMs: Long = 1000L / 12L
    private var pushedFrameCount: Long = 0

    fun switchCamera() {
        Log.i(TAG, "switchCamera requested, isFrontBefore=$isFrontCamera")
        isFrontCamera = !isFrontCamera
        isCameraSwitched = true
        Log.i(TAG, "switchCamera apply, isFrontAfter=$isFrontCamera")
        // 切换前后摄后按初始化路径重建预览旋转，避免后摄渲染矩阵异常导致无画面。
        setupPreviewRenderer(surfaceWidth, surfaceHeight, setPreviewRotation = true)
        setupCameraPreview()
    }

    init {
        applyDevicePreviewProfile()
        setEGLContextClientVersion(2)
        setRenderer(this)
        MtSharedPreferences.getInstance().init(context, FBEffect.shareInstance())
        renderMode = RENDERMODE_WHEN_DIRTY
        camera = MtCamera(mContext)
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        Log.i(TAG, "onSurfaceCreated")
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        post {
            setAspectRatio(imageHeight, imageWidth)
        }
        setupPreviewRenderer(width, height, setPreviewRotation = true)
        setupCameraPreview()
    }

    override fun onDrawFrame(gl: GL10?) {
        // 先消费最新相机纹理，再进行美颜处理与渲染，避免读取到上一帧/空帧。
        surfaceTexture?.updateTexImage()
        if (isCameraSwitched) {
            FBEffect.shareInstance().releaseTextureOESRenderer()
            isRenderInit = false
            isCameraSwitched = false
        }
        if (!isRenderInit) {
            MtSharedPreferences.getInstance().initAllSPValues()
            FBEffect.shareInstance().releaseTextureOESRenderer()
            isRenderInit = FBEffect.shareInstance().initTextureOESRenderer(imageWidth, imageHeight, mtRotation, isFrontCamera, 5)
        }
        textureId = FBEffect.shareInstance().processTextureOES(oesTextureId)
        previewRenderer?.render(textureId)
        if (MtPlugin.shouldPushToAgora) {
            val now = System.currentTimeMillis()
            if (now - lastPushTsMs < pushIntervalMs) {
                return
            }
            lastPushTsMs = now
            // 推流统一按相机预览档位读取，避免 viewport 受 UI 布局影响造成画面压缩/留黑边。
            // 结合 holder.setFixedSize(imageWidth, imageHeight)，可保证 glReadPixels 读取范围有效。
            val captureWidth = imageWidth
            val captureHeight = imageHeight

            val rowStride = captureWidth * 4
            val bufferSize = rowStride * captureHeight
            val buffer = ByteBuffer.allocateDirect(bufferSize)
            buffer.order(ByteOrder.nativeOrder())
            // 显式绑定默认帧缓冲，避免部分机型上 glReadPixels 读到黑缓冲。
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            GLES20.glPixelStorei(GLES20.GL_PACK_ALIGNMENT, 1)
            GLES20.glReadPixels(
                0,
                0,
                captureWidth,
                captureHeight,
                GLES20.GL_RGBA,
                GLES20.GL_UNSIGNED_BYTE,
                buffer
            )
            val byteArray = ByteArray(buffer.remaining())
            buffer.get(byteArray)
            pushedFrameCount += 1
            if (pushedFrameCount % 30L == 0L) {
                var lumaAcc = 0L
                var count = 0
                var i = 0
                val step = 16 * 4
                while (i + 2 < byteArray.size && count < 2000) {
                    val r = byteArray[i].toInt() and 0xFF
                    val g = byteArray[i + 1].toInt() and 0xFF
                    val b = byteArray[i + 2].toInt() and 0xFF
                    lumaAcc += (r + g + b) / 3
                    count += 1
                    i += step
                }
                if (count > 0) {
                    val avg = lumaAcc / count
                    Log.i(
                        TAG,
                        "agora push frame sample luma=$avg size=${captureWidth}x${captureHeight} " +
                            "surface=${surfaceWidth}x${surfaceHeight} preview=${imageWidth}x${imageHeight}",
                    )
                }
            }
            uiHandler.post {
                val data = mapOf<String, Any>(
                    "width" to captureWidth,
                    "height" to captureHeight,
                    // 对齐 Agora ExternalVideoFrame 约定：stride 使用像素数，不是字节数。
                    "stride" to captureWidth,
                    "bytes" to ensureOpaqueAlphaRgba(byteArray)
                )
                MtPlugin.beautyChannel.invokeMethod("onFrame", data)
            }
        }
    }

    private fun setLayoutParams(width: Int, height: Int) {
        uiHandler.post {
            val params: FrameLayout.LayoutParams = FrameLayout.LayoutParams(width, height)
            params.gravity = Gravity.CENTER
            layoutParams = params
        }
    }

    fun release() {
        camera.releaseCamera()
        FBEffect.shareInstance().releaseTextureOESRenderer()
        isRenderInit = false
    }

    private fun setupPreviewRenderer(width: Int, height: Int, setPreviewRotation: Boolean) {
        surfaceWidth = width
        surfaceHeight = height
        surfaceWidthF = width.toFloat()
        surfaceHeightF = height.toFloat()
        previewRenderer = FBPreviewRenderer(width, height)
        if (setPreviewRotation) {
            val previewRotation = if (isFrontCamera) 270 else 90
            previewRenderer?.setPreviewRotation(previewRotation)
            Log.i(TAG, "setupPreviewRenderer rotation=$previewRotation isFront=$isFrontCamera size=${width}x$height")
        }
        previewRenderer?.create(isFrontCamera)
    }

    private fun setupCameraPreview() {
        oesTextureId = FBGLUtils.getExternalOESTextureID()
        surfaceTexture?.release()
        surfaceTexture = SurfaceTexture(oesTextureId)
        surfaceTexture?.setOnFrameAvailableListener { this.requestRender() }
        mtRotation = if (isFrontCamera) FBRotationEnum.FBRotationClockwise270 else FBRotationEnum.FBRotationClockwise90
        val cameraId = if (isFrontCamera) Camera.CameraInfo.CAMERA_FACING_FRONT else Camera.CameraInfo.CAMERA_FACING_BACK
        val candidates = buildPreviewCandidates()
        var openedAndPreviewing = false
        for ((w, h) in candidates) {
            camera.releaseCamera()
            val success = camera.openCamera(cameraId, w, h)
            if (!success) {
                Log.w(TAG, "openCamera failed for preview size=${w}x$h")
                continue
            }
            imageWidth = w
            imageHeight = h
            // 小窗预览场景下，默认 surface buffer 会随 View 变小，导致远端推流分辨率被压低。
            // 固定底层 buffer 为相机档位，兼顾小窗显示与高清推流。
            holder.setFixedSize(imageWidth, imageHeight)
            val surfaceBound = camera.setPreviewSurface(surfaceTexture)
            if (!surfaceBound) {
                Log.w(TAG, "setPreviewSurface failed for preview size=${imageWidth}x$imageHeight")
                continue
            }
            val previewStarted = camera.startPreview()
            if (!previewStarted) {
                Log.w(TAG, "startPreview failed for preview size=${imageWidth}x$imageHeight")
                continue
            }
            openedAndPreviewing = true
            Log.i(
                TAG,
                "camera preview ready with size=${imageWidth}x$imageHeight, cameraId=$cameraId",
            )
            uiHandler.post {
                MtPlugin.beautyChannel.invokeMethod(
                    "previewReady",
                    mapOf(
                        "width" to imageWidth,
                        "height" to imageHeight,
                        "cameraId" to cameraId,
                    ),
                )
            }
            break
        }
        if (!openedAndPreviewing) {
            Log.e(TAG, "setupCameraPreview failed: all preview profiles failed")
            if (!isFrontCamera) {
                Log.w(TAG, "back camera failed, fallback to front camera")
                isFrontCamera = true
                isCameraSwitched = true
                setupPreviewRenderer(surfaceWidth, surfaceHeight, setPreviewRotation = true)
                setupCameraPreview()
            }
            return
        }
    }

    private fun applyDevicePreviewProfile() {
        val manufacturer = Build.MANUFACTURER?.lowercase() ?: ""
        val brand = Build.BRAND?.lowercase() ?: ""
        val model = Build.MODEL ?: ""
        // 全机型统一：高清优先，失败时自动降级到后备档位。
        imageWidth = 1280
        imageHeight = 720
        Log.i(
            TAG,
            "Use unified HD-first preview profile: $manufacturer/$brand, model=$model, size=${imageWidth}x$imageHeight",
        )
    }

    private fun buildPreviewCandidates(): List<Pair<Int, Int>> {
        val candidates = mutableListOf<Pair<Int, Int>>()
        fun add(width: Int, height: Int) {
            val pair = width to height
            if (!candidates.contains(pair)) {
                candidates.add(pair)
            }
        }

        add(imageWidth, imageHeight)
        add(1280, 720)
        add(960, 540)
        add(640, 480)
        return candidates
    }

    fun ensureOpaqueAlphaRgba(rgba: ByteArray): ByteArray {
        val out = ByteArray(rgba.size)
        var i = 0
        while (i < rgba.size) {
            out[i] = rgba[i]
            out[i + 1] = rgba[i + 1]
            out[i + 2] = rgba[i + 2]
            // 某些机型 glReadPixels 返回 alpha 接近 0，会造成编码后“看似解码正常但画面发黑”。
            // 外部视频源统一使用不透明 alpha。
            out[i + 3] = 0xFF.toByte()
            i += 4
        }
        return out
    }
}
