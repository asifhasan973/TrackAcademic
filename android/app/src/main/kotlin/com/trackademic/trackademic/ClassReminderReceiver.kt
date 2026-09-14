package com.trackademic.trackademic

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class ClassReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val scheduleId = intent.getStringExtra("scheduleId") ?: return
        val courseCode = intent.getStringExtra("courseCode") ?: "Class"
        val courseName = intent.getStringExtra("courseName") ?: ""
        val room = intent.getStringExtra("room") ?: ""
        val startTime = intent.getStringExtra("startTime") ?: ""

        val title = "Upcoming Class: $courseCode"
        val body = buildString {
            if (courseName.isNotEmpty()) append("$courseName\n")
            append("Starts at $startTime")
            if (room.isNotEmpty()) append(" in Room $room")
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("type", "class_reminder")
            putExtra("scheduleId", scheduleId)
            putExtra("courseCode", courseCode)
        }

        val notificationId = scheduleId.hashCode()
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, NotificationHelper.CHANNEL_REMINDERS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted
        }

        // Clean up from SharedPreferences since it has fired
        NotificationHelper.cancelClassReminder(context, scheduleId)
    }
}
