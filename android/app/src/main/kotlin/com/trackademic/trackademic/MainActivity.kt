package com.trackademic.trackademic

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val STORAGE_CHANNEL = "com.trackademic/storage_channel"
    private val NOTIFICATION_CHANNEL = "com.trackademic/notification_channel"

    private var pendingNotificationPayload: Map<String, Any?>? = null
    private var notificationMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationHelper.createNotificationChannels(applicationContext)
        extractNotificationPayload(intent)
    }

    override fun onNewIntent(@NonNull intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractNotificationPayload(intent)
        pendingNotificationPayload?.let { payload ->
            notificationMethodChannel?.invokeMethod("onNotificationTapped", payload)
        }
    }

    private fun extractNotificationPayload(intent: Intent?) {
        if (intent == null) return
        val extras = intent.extras ?: return
        val map = mutableMapOf<String, Any?>()
        for (key in extras.keySet()) {
            map[key] = extras.get(key)
        }
        if (map.containsKey("type") || map.containsKey("courseId") || map.containsKey("scheduleId")) {
            pendingNotificationPayload = map
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Notification Platform Channel
        notificationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        try {
                            val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                            val title = call.argument<String>("title") ?: "TrackAcademic"
                            val body = call.argument<String>("body") ?: ""
                            val payload = call.argument<Map<String, Any?>>("payload") ?: emptyMap()

                            NotificationHelper.showSystemNotification(applicationContext, id, title, body, payload)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOTIFY_FAILED", e.localizedMessage, null)
                        }
                    }
                    "scheduleClassReminder" -> {
                        try {
                            val scheduleId = call.argument<String>("scheduleId") ?: ""
                            val courseCode = call.argument<String>("courseCode") ?: ""
                            val courseName = call.argument<String>("courseName") ?: ""
                            val room = call.argument<String>("room") ?: ""
                            val startTime = call.argument<String>("startTime") ?: ""
                            val triggerTimeMillis = (call.argument<Number>("triggerTimeMillis"))?.toLong() ?: 0L

                            val ok = NotificationHelper.scheduleClassReminder(
                                applicationContext,
                                scheduleId,
                                courseCode,
                                courseName,
                                room,
                                startTime,
                                triggerTimeMillis
                            )
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_FAILED", e.localizedMessage, null)
                        }
                    }
                    "cancelClassReminder" -> {
                        try {
                            val scheduleId = call.argument<String>("scheduleId") ?: ""
                            val ok = NotificationHelper.cancelClassReminder(applicationContext, scheduleId)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.localizedMessage, null)
                        }
                    }
                    "cancelAllClassReminders" -> {
                        try {
                            val ok = NotificationHelper.cancelAllClassReminders(applicationContext)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("CANCEL_ALL_FAILED", e.localizedMessage, null)
                        }
                    }
                    "getPendingNotificationPayload" -> {
                        val payload = pendingNotificationPayload
                        pendingNotificationPayload = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 2. Storage Platform Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val filename = call.argument<String>("filename") ?: "export.dat"
                    val bytes = call.argument<ByteArray>("bytes") ?: byteArrayOf()
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val resolver = applicationContext.contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/TrackAcademic")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }

                        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                        val itemUri = resolver.insert(collection, contentValues)

                        if (itemUri == null) {
                            result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val outputStream = resolver.openOutputStream(itemUri)
                            if (outputStream == null) {
                                resolver.delete(itemUri, null, null)
                                result.error("STREAM_FAILED", "Failed to open output stream for download target", null)
                                return@setMethodCallHandler
                            }

                            outputStream.use { stream ->
                                stream.write(bytes)
                                stream.flush()
                            }

                            contentValues.clear()
                            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(itemUri, contentValues, null, null)

                            // Query actual disambiguated file name from MediaStore cursor
                            var actualName = filename
                            resolver.query(itemUri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                                    if (nameIdx >= 0) {
                                        actualName = cursor.getString(nameIdx) ?: filename
                                    }
                                }
                            }

                            result.success(
                                mapOf(
                                    "displayPath" to "Download/TrackAcademic/$actualName",
                                    "uri" to itemUri.toString(),
                                    "mimeType" to mimeType
                                )
                            )
                        } catch (e: Exception) {
                            // Clean up incomplete MediaStore entry
                            try {
                                resolver.delete(itemUri, null, null)
                            } catch (ignored: Exception) {}
                            result.error("SAVE_FAILED", e.localizedMessage, null)
                        }
                    } else {
                        // Android < 29 (API <= 28): runtime permission check
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                            result.error("PERMISSION_DENIED", "Storage permission required to save downloads on this device.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            val trackacademicDir = File(downloadsDir, "TrackAcademic")
                            if (!trackacademicDir.exists()) {
                                trackacademicDir.mkdirs()
                            }

                            // Disambiguate filename to prevent unintended overwrites
                            var targetFile = File(trackacademicDir, filename)
                            var counter = 1
                            val nameWithoutExt = filename.substringBeforeLast(".")
                            val ext = filename.substringAfterLast(".", "")
                            while (targetFile.exists()) {
                                val newName = if (ext.isNotEmpty()) "$nameWithoutExt ($counter).$ext" else "$filename ($counter)"
                                targetFile = File(trackacademicDir, newName)
                                counter++
                            }

                            FileOutputStream(targetFile).use { out ->
                                out.write(bytes)
                                out.flush()
                            }

                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(targetFile.absolutePath),
                                arrayOf(mimeType),
                                null
                            )

                            val contentUri = try {
                                androidx.core.content.FileProvider.getUriForFile(
                                    applicationContext,
                                    "${applicationContext.packageName}.fileprovider",
                                    targetFile
                                )
                            } catch (e: Exception) {
                                Uri.fromFile(targetFile)
                            }

                            result.success(
                                mapOf(
                                    "displayPath" to targetFile.absolutePath,
                                    "uri" to contentUri.toString(),
                                    "mimeType" to mimeType
                                )
                            )
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.localizedMessage, null)
                        }
                    }
                }
                "openFile" -> {
                    try {
                        val uriStr = call.argument<String>("uri") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        val parsedUri = Uri.parse(uriStr)
                        val finalUri = if (parsedUri.scheme == "file") {
                            val f = File(parsedUri.path ?: "")
                            androidx.core.content.FileProvider.getUriForFile(
                                applicationContext,
                                "${applicationContext.packageName}.fileprovider",
                                f
                            )
                        } else {
                            parsedUri
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(finalUri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        for (resolveInfo in resInfoList) {
                            grantUriPermission(resolveInfo.activityInfo.packageName, finalUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(intent, "Open file").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.localizedMessage, null)
                    }
                }
                "shareFile" -> {
                    try {
                        val uriStr = call.argument<String>("uri") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        val parsedUri = Uri.parse(uriStr)
                        val finalUri = if (parsedUri.scheme == "file") {
                            val f = File(parsedUri.path ?: "")
                            androidx.core.content.FileProvider.getUriForFile(
                                applicationContext,
                                "${applicationContext.packageName}.fileprovider",
                                f
                            )
                        } else {
                            parsedUri
                        }

                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, finalUri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                        for (resolveInfo in resInfoList) {
                            grantUriPermission(resolveInfo.activityInfo.packageName, finalUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        val chooser = Intent.createChooser(intent, "Share file").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
