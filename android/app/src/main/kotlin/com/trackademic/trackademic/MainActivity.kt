package com.trackademic.trackademic

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trackademic/storage_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    try {
                        val filename = call.argument<String>("filename") ?: "export.dat"
                        val bytes = call.argument<ByteArray>("bytes") ?: byteArrayOf()
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val contentValues = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/TrackAcademic")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }

                            val resolver = applicationContext.contentResolver
                            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                            val itemUri = resolver.insert(collection, contentValues)

                            if (itemUri != null) {
                                resolver.openOutputStream(itemUri)?.use { stream ->
                                    stream.write(bytes)
                                    stream.flush()
                                }
                                contentValues.clear()
                                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                                resolver.update(itemUri, contentValues, null, null)

                                result.success(
                                    mapOf(
                                        "displayPath" to "Downloads/TrackAcademic/$filename",
                                        "uri" to itemUri.toString(),
                                        "mimeType" to mimeType
                                    )
                                )
                            } else {
                                result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                            }
                        } else {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            val trackacademicDir = File(downloadsDir, "TrackAcademic")
                            if (!trackacademicDir.exists()) {
                                trackacademicDir.mkdirs()
                            }
                            val targetFile = File(trackacademicDir, filename)
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
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.localizedMessage, null)
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

                        val resInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
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

                        val resInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
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
