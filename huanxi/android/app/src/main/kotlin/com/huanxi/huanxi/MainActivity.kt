package com.huanxi.huanxi

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var incomingCallChannel: MethodChannel? = null
    private var pendingIncomingCall: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureIncomingCall(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIncomingCall(intent)
        pendingIncomingCall?.let { payload ->
            incomingCallChannel?.invokeMethod("openIncomingCall", payload)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "huanxi/screenshot_security"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "apply" -> {
                        val enabled = call.argument<Boolean>("androidPreventScreenshotEnabled") ?: true
                        applyScreenshotSecurity(enabled)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("SCREENSHOT_SECURITY_ERROR", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "huanxi/call_keep_alive"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isServiceRunning" -> {
                        result.success(CallKeepAliveService.isRunning)
                    }
                    "startOnlineMode" -> {
                        CallKeepAliveService.startOnlineMode(this)
                        result.success(null)
                    }
                    "stopOnlineMode" -> {
                        CallKeepAliveService.stop(this)
                        result.success(null)
                    }
                    "startCallMode" -> {
                        val callId = call.argument<Int>("callId") ?: 0
                        CallKeepAliveService.startCallMode(this, callId)
                        result.success(null)
                    }
                    "stopCallMode" -> {
                        CallKeepAliveService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("CALL_KEEP_ALIVE_ERROR", error.message, null)
            }
        }

        incomingCallChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "huanxi/incoming_call_notification"
        )
        incomingCallChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "showIncomingCall" -> {
                        val args = call.arguments as? Map<*, *>
                        val callId = (args?.get("callId") as? Number)?.toInt() ?: 0
                        val peerUserId = (args?.get("peerUserId") as? Number)?.toInt() ?: 0
                        val peerName = args?.get("peerName")?.toString()?.takeIf { it.isNotBlank() } ?: "用户"
                        val peerAvatar = args?.get("peerAvatar")?.toString()
                        val leftSeconds = (args?.get("leftSeconds") as? Number)?.toInt() ?: 30
                        if (callId <= 0 || peerUserId <= 0) {
                            result.error("INVALID_INCOMING_CALL", "callId or peerUserId is invalid", null)
                            return@setMethodCallHandler
                        }
                        IncomingCallNotification.show(
                            this,
                            callId,
                            peerUserId,
                            peerName,
                            peerAvatar,
                            leftSeconds
                        )
                        result.success(null)
                    }
                    "cancelIncomingCall" -> {
                        val args = call.arguments as? Map<*, *>
                        val callId = (args?.get("callId") as? Number)?.toInt() ?: 0
                        if (callId > 0) {
                            IncomingCallNotification.cancel(this, callId)
                        }
                        result.success(null)
                    }
                    "takeLaunchIncomingCall" -> {
                        val payload = pendingIncomingCall
                        pendingIncomingCall = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("INCOMING_CALL_NOTIFICATION_ERROR", error.message, null)
            }
        }
    }

    private fun captureIncomingCall(intent: Intent?) {
        pendingIncomingCall = IncomingCallNotification.payloadFromIntent(intent)
    }

    private fun applyScreenshotSecurity(enabled: Boolean) {
        if (enabled) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
