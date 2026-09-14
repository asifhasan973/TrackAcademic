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
        val courseId = intent.getStringExtra("courseId") ?: ""
        val userId = intent.getStringExtra("userId") ?: ""
        val courseCode = intent.getStringExtra("courseCode") ?: "Class"
        val courseName = intent.getStringExtra("courseName") ?: ""
        val room = intent.getStringExtra("room") ?: ""
        val startTime = intent.getStringExtra("startTime") ?: ""
        val dayOfWeek = intent.getIntExtra("dayOfWeek", -1)
        val leadMinutes = intent.getIntExtra("leadMinutes", 15)

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
            putExtra("courseId", courseId)
            putExtra("userId", userId)
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

        // Subsequent weekly recurrence: if this was a recurring timetable entry (dayOfWeek in 1..7),
        // recalculate and schedule next week's occurrence with persisted recurrence metadata.
        if (dayOfWeek in 1..7 && startTime.isNotEmpty()) {
            val now = System.currentTimeMillis()
            val nextTrigger = NotificationHelper.computeNextOccurrenceMillis(dayOfWeek, startTime, leadMinutes, now)
            if (nextTrigger > now) {
                NotificationHelper.scheduleClassReminder(
                    context,
                    scheduleId,
                    courseId,
                    userId,
                    courseCode,
                    courseName,
                    room,
                    startTime,
                    dayOfWeek,
                    leadMinutes,
                    nextTrigger
                )
            } else {
                NotificationHelper.cancelClassReminder(context, scheduleId)
            }
        } else {
            // Non-recurring one-off reminder; clean up
            NotificationHelper.cancelClassReminder(context, scheduleId)
        }
    }
}

