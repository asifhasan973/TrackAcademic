package com.trackademic.trackademic

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar
import java.util.TimeZone
import org.json.JSONObject

object NotificationHelper {
    const val CHANNEL_GENERAL = "trackacademic_general"
    const val CHANNEL_REMINDERS = "trackacademic_reminders"
    private const val PREFS_NAME = "trackacademic_reminders_prefs"

    fun createNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // General push channel
            val generalChannel = NotificationChannel(
                CHANNEL_GENERAL,
                "General Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "TrackAcademic course and attendance notifications"
                enableLights(true)
                enableVibration(true)
            }

            // Class reminders channel
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val remindersChannel = NotificationChannel(
                CHANNEL_REMINDERS,
                "Class Timetable Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Timetable reminders for upcoming classes"
                enableLights(true)
                enableVibration(true)
                setSound(soundUri, audioAttributes)
            }

            notificationManager.createNotificationChannel(generalChannel)
            notificationManager.createNotificationChannel(remindersChannel)
        }
    }

    fun showSystemNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: Map<String, Any?>
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            for ((key, value) in payload) {
                if (value != null) {
                    putExtra(key, value.toString())
                }
            }
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_GENERAL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (e: SecurityException) {
            // Android 13+ POST_NOTIFICATIONS permission not granted
        }
    }

    fun computeNextOccurrenceMillis(
        dayOfWeek: Int,
        startTime: String,
        leadMinutes: Int,
        referenceMillis: Long
    ): Long {
        val parts = startTime.split(":")
        if (parts.size < 2) return 0L
        val hour = parts[0].toIntOrNull() ?: return 0L
        val minute = parts[1].toIntOrNull() ?: return 0L

        val calendar = Calendar.getInstance(TimeZone.getDefault())
        calendar.timeInMillis = referenceMillis
        val currentWeekday = calendar.get(Calendar.DAY_OF_WEEK)

        // Map ISO dayOfWeek (1=Mon ... 7=Sun) to java.util.Calendar day (Calendar.SUNDAY=1 ... Calendar.SATURDAY=7)
        val targetCalDay = when (dayOfWeek) {
            1 -> Calendar.MONDAY
            2 -> Calendar.TUESDAY
            3 -> Calendar.WEDNESDAY
            4 -> Calendar.THURSDAY
            5 -> Calendar.FRIDAY
            6 -> Calendar.SATURDAY
            7 -> Calendar.SUNDAY
            else -> return 0L
        }

        var daysUntil = (targetCalDay - currentWeekday) % 7
        if (daysUntil < 0) daysUntil += 7

        calendar.add(Calendar.DAY_OF_YEAR, daysUntil)
        calendar.set(Calendar.HOUR_OF_DAY, hour)
        calendar.set(Calendar.MINUTE, minute)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        calendar.add(Calendar.MINUTE, -leadMinutes)

        if (calendar.timeInMillis <= referenceMillis) {
            calendar.add(Calendar.DAY_OF_YEAR, 7)
        }

        return calendar.timeInMillis
    }

    fun scheduleClassReminder(
        context: Context,
        scheduleId: String,
        courseId: String = "",
        userId: String = "",
        courseCode: String,
        courseName: String,
        room: String,
        startTime: String,
        dayOfWeek: Int = -1,
        leadMinutes: Int = 15,
        triggerTimeMillis: Long
    ): Boolean {
        if (triggerTimeMillis <= System.currentTimeMillis()) {
            return false
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        val intent = Intent(context, ClassReminderReceiver::class.java).apply {
            action = "com.trackademic.ACTION_CLASS_REMINDER"
            putExtra("scheduleId", scheduleId)
            putExtra("courseId", courseId)
            putExtra("userId", userId)
            putExtra("courseCode", courseCode)
            putExtra("courseName", courseName)
            putExtra("room", room)
            putExtra("startTime", startTime)
            putExtra("dayOfWeek", dayOfWeek)
            putExtra("leadMinutes", leadMinutes)
            putExtra("triggerTimeMillis", triggerTimeMillis)
        }

        val requestCode = scheduleId.hashCode()
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
                    } else {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
                    }
                } else {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
                }
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            }

            // Persist to SharedPreferences for reboot recovery & recurrence
            saveReminderToPrefs(
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
                triggerTimeMillis
            )
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun cancelClassReminder(context: Context, scheduleId: String): Boolean {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        val intent = Intent(context, ClassReminderReceiver::class.java).apply {
            action = "com.trackademic.ACTION_CLASS_REMINDER"
        }
        val requestCode = scheduleId.hashCode()
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }

        removeReminderFromPrefs(context, scheduleId)
        return true
    }

    fun cancelAllClassReminders(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val allEntries = prefs.all
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

        for ((scheduleId, _) in allEntries) {
            val intent = Intent(context, ClassReminderReceiver::class.java).apply {
                action = "com.trackademic.ACTION_CLASS_REMINDER"
            }
            val requestCode = scheduleId.hashCode()
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pendingIntent != null && alarmManager != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }

        prefs.edit().clear().apply()
        return true
    }

    fun rescheduleAllFromPrefs(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val editor = prefs.edit()

        for ((scheduleId, jsonStr) in prefs.all) {
            if (jsonStr is String) {
                try {
                    val obj = JSONObject(jsonStr)
                    val triggerTime = obj.getLong("triggerTimeMillis")
                    val dayOfWeek = obj.optInt("dayOfWeek", -1)
                    val leadMinutes = obj.optInt("leadMinutes", 15)
                    val startTime = obj.optString("startTime", "")

                    if (triggerTime > now) {
                        scheduleClassReminder(
                            context,
                            scheduleId,
                            obj.optString("courseId", ""),
                            obj.optString("userId", ""),
                            obj.getString("courseCode"),
                            obj.getString("courseName"),
                            obj.getString("room"),
                            startTime,
                            dayOfWeek,
                            leadMinutes,
                            triggerTime
                        )
                    } else if (dayOfWeek in 1..7 && startTime.isNotEmpty()) {
                        // Recalculate next upcoming weekly occurrence timezone-aware
                        val nextTrigger = computeNextOccurrenceMillis(dayOfWeek, startTime, leadMinutes, now)
                        if (nextTrigger > now) {
                            scheduleClassReminder(
                                context,
                                scheduleId,
                                obj.optString("courseId", ""),
                                obj.optString("userId", ""),
                                obj.getString("courseCode"),
                                obj.getString("courseName"),
                                obj.getString("room"),
                                startTime,
                                dayOfWeek,
                                leadMinutes,
                                nextTrigger
                            )
                        } else {
                            editor.remove(scheduleId)
                        }
                    } else {
                        // Expired one-off reminder
                        editor.remove(scheduleId)
                    }
                } catch (e: Exception) {
                    editor.remove(scheduleId)
                }
            }
        }
        editor.apply()
    }

    private fun saveReminderToPrefs(
        context: Context,
        scheduleId: String,
        courseId: String,
        userId: String,
        courseCode: String,
        courseName: String,
        room: String,
        startTime: String,
        dayOfWeek: Int,
        leadMinutes: Int,
        triggerTimeMillis: Long
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = JSONObject().apply {
            put("scheduleId", scheduleId)
            put("courseId", courseId)
            put("userId", userId)
            put("courseCode", courseCode)
            put("courseName", courseName)
            put("room", room)
            put("startTime", startTime)
            put("dayOfWeek", dayOfWeek)
            put("leadMinutes", leadMinutes)
            put("triggerTimeMillis", triggerTimeMillis)
        }
        prefs.edit().putString(scheduleId, json.toString()).apply()
    }

    private fun removeReminderFromPrefs(context: Context, scheduleId: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(scheduleId).apply()
    }
}

