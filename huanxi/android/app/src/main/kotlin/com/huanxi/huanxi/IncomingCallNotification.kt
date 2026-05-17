package com.huanxi.huanxi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object IncomingCallNotification {
    const val ACTION_INCOMING_CALL = "com.huanxi.huanxi.action.INCOMING_CALL"
    const val EXTRA_CALL_ID = "callId"
    const val EXTRA_PEER_USER_ID = "peerUserId"
    const val EXTRA_PEER_NAME = "peerName"
    const val EXTRA_PEER_AVATAR = "peerAvatar"
    const val EXTRA_LEFT_SECONDS = "leftSeconds"

    private const val CHANNEL_ID = "huanxi_incoming_call"
    private const val NOTIFICATION_BASE_ID = 3000

    fun show(
        context: Context,
        callId: Int,
        peerUserId: Int,
        peerName: String,
        peerAvatar: String?,
        leftSeconds: Int
    ) {
        createNotificationChannel(context)
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_INCOMING_CALL
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_PEER_USER_ID, peerUserId)
            putExtra(EXTRA_PEER_NAME, peerName)
            putExtra(EXTRA_PEER_AVATAR, peerAvatar ?: "")
            putExtra(EXTRA_LEFT_SECONDS, leftSeconds)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            callId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("视频通话邀请")
            .setContentText("${peerName}邀请你视频通话")
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(notificationId(callId), notification)
    }

    fun cancel(context: Context, callId: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationId(callId))
    }

    fun payloadFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != ACTION_INCOMING_CALL) return null
        val callId = intent.getIntExtra(EXTRA_CALL_ID, 0)
        val peerUserId = intent.getIntExtra(EXTRA_PEER_USER_ID, 0)
        if (callId <= 0 || peerUserId <= 0) return null
        return mapOf(
            EXTRA_CALL_ID to callId,
            EXTRA_PEER_USER_ID to peerUserId,
            EXTRA_PEER_NAME to (intent.getStringExtra(EXTRA_PEER_NAME) ?: "用户"),
            EXTRA_PEER_AVATAR to (intent.getStringExtra(EXTRA_PEER_AVATAR) ?: ""),
            EXTRA_LEFT_SECONDS to intent.getIntExtra(EXTRA_LEFT_SECONDS, 30)
        )
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "视频来电",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "后台接听模式下的视频通话邀请"
        channel.lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        manager.createNotificationChannel(channel)
    }

    private fun notificationId(callId: Int): Int = NOTIFICATION_BASE_ID + callId
}
