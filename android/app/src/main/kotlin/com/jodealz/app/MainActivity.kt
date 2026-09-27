package com.jodealz.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    /**
     * Creates the default FCM channel once. Android keeps the user's choices
     * (importance, sound, blocked) per channel, so it must not be deleted and
     * re-created; to change the sound, ship a new channel ID instead.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val soundUri = Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://$packageName/${R.raw.jodealz_notification}"
        )
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()

        val channel = NotificationChannel(
            CHANNEL_ID,
            "JO-Dealz Notifications",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for JO-Dealz deals, order status, and messages."
            enableLights(true)
            enableVibration(true)
            setSound(soundUri, audioAttributes)
        }
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        manager.createNotificationChannel(channel)
    }

    companion object {
        // Bumped from "jodealz_notification_channel": the old channel was
        // created without the custom sound, and a channel's sound is fixed.
        private const val CHANNEL_ID = "jodealz_notifications_v2"
        private const val LEGACY_CHANNEL_ID = "jodealz_notification_channel"
    }
}
