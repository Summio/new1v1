@file:Suppress("DEPRECATION")

package com.toivan.mtcamera.mt_plugin.view

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.Camera
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
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

    //用于标记前后置镜头
    private var isFrontCamera = true

    private var isCameraSwitched = false

    private var mtRotation: FBRotationEnum? = null


    private var previewRenderer: FBPreviewRenderer? = null


    private var isRenderInit = false

    /**
     * 相机采集的宽高
     */
    private val imageWidth = 1280

    /**
     * 相机采集的宽高
     */
    private var imageHeight: Int = 720


    /**
     * 页面显示的宽高
     */
    private var surfaceWidth = 0
    private var surfaceHeight: Int = 0

    private var surfaceWidthF = 0f

    private var surfaceHeightF = 0f

    private var textureId = 2

    fun switchCamera() {
        val fromFront = isFrontCamera
        isFrontCamera = !isFrontCamera
        isCameraSwitched = true

        val cameraId =
            if (isFrontCamera) Camera.CameraInfo.CAMERA_FACING_FRONT else Camera.CameraInfo.CAMERA_FACING_BACK

        mtRotation = if (isFrontCamera) {
            FBRotationEnum.FBRotationClockwise270
        } else {
            FBRotationEnum.FBRotationClockwise0
        }

        val currentSurface = surfaceTexture
        if (currentSurface == null) {
            isFrontCamera = fromFront
            isCameraSwitched = false
            uiHandler.post {
                MtPlugin.beautyChannel.invokeMethod(
                    "cameraSwitchResult",
                    mapOf(
                        "success" to false,
                        "from" to if (fromFront) "front" else "back",
                        "to" to if (isFrontCamera) "front" else "back",
                        "cameraId" to cameraId,
                        "width" to imageWidth,
                        "height" to imageHeight
                    )
                )
            }
            return
        }

        camera.releaseCamera()

        camera.openCamera(cameraId, imageWidth, imageHeight)
        camera.setPreviewSurface(currentSurface)

        camera.startPreview()

        uiHandler.post {
            MtPlugin.beautyChannel.invokeMethod(
                "cameraSwitchResult",
                mapOf(
                    "success" to true,
                    "from" to if (fromFront) "front" else "back",
                    "to" to if (isFrontCamera) "front" else "back",
                    "cameraId" to cameraId,
                    "width" to imageWidth,
                    "height" to imageHeight
                )
            )
            MtPlugin.beautyChannel.invokeMethod(
                "previewReady",
                mapOf(
                    "width" to imageWidth,
                    "height" to imageHeight,
                    "rawWidth" to imageWidth,
                    "rawHeight" to imageHeight,
                    "cameraId" to cameraId
                )
            )
        }

    }


    //进行初始化
    init {
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
        surfaceWidth = width
        surfaceHeight = height
        surfaceWidthF = width.toFloat()
        surfaceHeightF = height.toFloat()

        post {
            setAspectRatio(imageHeight, imageWidth)
        }


        previewRenderer = FBPreviewRenderer(width, height)
        previewRenderer?.setPreviewRotation(270)
        previewRenderer?.create(isFrontCamera)

        oesTextureId = FBGLUtils.getExternalOESTextureID()

        surfaceTexture = SurfaceTexture(oesTextureId)

        surfaceTexture?.setOnFrameAvailableListener { this.requestRender() }

        val cameraId =
            if (isFrontCamera) Camera.CameraInfo.CAMERA_FACING_FRONT else Camera.CameraInfo.CAMERA_FACING_BACK

        mtRotation = if (isFrontCamera) FBRotationEnum.FBRotationClockwise270 else FBRotationEnum.FBRotationClockwise0

        camera.openCamera(cameraId, imageWidth, imageHeight)

        camera.setPreviewSurface(surfaceTexture)

        camera.startPreview()

    }

    override fun onDrawFrame(gl: GL10?) {

        if (isCameraSwitched) {
            FBEffect.shareInstance().releaseTextureOESRenderer()
            isRenderInit = false
            isCameraSwitched = false

        }
        if (!isRenderInit) {

            MtSharedPreferences.getInstance().initAllSPValues()
            FBEffect.shareInstance().releaseTextureOESRenderer();
            //添加渲染
            isRenderInit = FBEffect.shareInstance().initTextureOESRenderer(imageWidth, imageHeight, mtRotation, isFrontCamera, 5);

        }
//        android.util.Log.d(TAG, "onDrawFrame: "+imageWidth+"×"+imageHeight)
        textureId = FBEffect.shareInstance().processTextureOES(oesTextureId)

        previewRenderer?.render(textureId)

        surfaceTexture?.updateTexImage()

        //Log.i(TAG, "shouldPushToAgora ${MtPlugin.shouldPushToAgora}")
        if (MtPlugin.shouldPushToAgora) {
            val viewport = IntArray(4)
            GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, viewport, 0)
            val captureWidth = viewport[2]
            val captureHeight = viewport[3]
            if (captureWidth <= 0 || captureHeight <= 0) {
                return
            }
            val rowStride = captureWidth * 4
            val bufferSize = rowStride * captureHeight

            val buffer = ByteBuffer.allocateDirect(bufferSize)
            buffer.order(ByteOrder.nativeOrder())
            GLES20.glReadPixels(0, 0, captureWidth, captureHeight, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)

            val byteArray = ByteArray(buffer.remaining())
            buffer.get(byteArray)

            uiHandler.post {
                val data = mapOf<String, Any>(
                    "width" to captureWidth,
                    "height" to captureHeight,
                    "stride" to rowStride,
                    "bytes" to rgbaToBgra(byteArray)
                )
                MtPlugin.beautyChannel.invokeMethod("onFrame", data)
            }
        }
    }


    //重新设置布局
    private fun setLayoutParams(width: Int, height: Int) {
        uiHandler.post {
            val params: FrameLayout.LayoutParams = FrameLayout.LayoutParams(width, height)
            params.gravity = Gravity.CENTER
            layoutParams = params
        }
    }

    fun release() {
        camera.releaseCamera()
        FBEffect.shareInstance().releaseTextureOESRenderer();
        isRenderInit = false;
    }

    fun rgbaToBgra(rgba: ByteArray): ByteArray {
        val bgra = ByteArray(rgba.size)
        var i = 0
        while (i < rgba.size) {
            val r = rgba[i]
            val g = rgba[i + 1]
            val b = rgba[i + 2]
            val a = rgba[i + 3]

            bgra[i] = b     // B
            bgra[i + 1] = g // G
            bgra[i + 2] = r // R
            bgra[i + 3] = a // A

            i += 4
        }
        return bgra
    }


}
