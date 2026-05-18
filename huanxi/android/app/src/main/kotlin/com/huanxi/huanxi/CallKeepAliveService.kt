package com.huanxi.huanxi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class CallKeepAliveService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra(EXTRA_MODE) ?: MODE_ONLINE
        val callId = intent?.getIntExtra(EXTRA_CALL_ID, 0) ?: 0
        try {
            startForeground(NOTIFICATION_ID, buildNotification(mode, callId))
        } catch (error: Throwable) {
            isRunning = false
            currentMode = null
            stopSelf()
            return START_NOT_STICKY
        }
        isRunning = true
        currentMode = mode
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        currentMode = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台接听",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "保持在线接听和通话状态"
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(mode: String, callId: Int): Notification {
        val title = if (mode == MODE_CALL) "通话中" else "正在保持在线"
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (callId > 0) {
            launchIntent.putExtra(EXTRA_CALL_ID, callId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
        if (mode == MODE_CALL) {
            builder.setContentText("点击返回通话")
        }
        return builder.build()
    }

    companion object {
        private const val CHANNEL_ID = "huanxi_call_keep_alive"
        private const val NOTIFICATION_ID = 1001
        private const val EXTRA_MODE = "mode"
        private const val EXTRA_CALL_ID = "call_id"
        private const val MODE_ONLINE = "online"
        private const val MODE_CALL = "call"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var currentMode: String? = null
            private set

        fun startOnlineMode(context: Context) {
            val intent = Intent(context, CallKeepAliveService::class.java)
                .putExtra(EXTRA_MODE, MODE_ONLINE)
            ContextCompat.startForegroundService(context, intent)
        }

        fun startCallMode(context: Context, callId: Int) {
            val intent = Intent(context, CallKeepAliveService::class.java)
                .putExtra(EXTRA_MODE, MODE_CALL)
                .putExtra(EXTRA_CALL_ID, callId)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallKeepAliveService::class.java))
        }
    }
}
