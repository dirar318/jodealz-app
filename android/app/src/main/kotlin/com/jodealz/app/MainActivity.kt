package com.jodealz.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "jodealz_notification_channel"
            val name = "JoDeals Notifications"
            val descriptionText = "Notifications for JoDeals deals, order status, and messages."
            val importance = NotificationManager.IMPORTANCE_HIGH
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Delete old channel if it exists to ensure any sound changes are picked up, since Android caches channel sounds.
            try {
                manager.deleteNotificationChannel(channelId)
            } catch (e: Exception) {
                // Ignore if it doesn't exist
            }

            val channel = NotificationChannel(channelId, name, importance).apply {
                description = descriptionText
                enableLights(true)
                enableVibration(true)
            }
            
            manager.createNotificationChannel(channel)
        }
    }
}
