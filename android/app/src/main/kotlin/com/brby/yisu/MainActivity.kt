package com.brby.yisu

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val updateChannelName = "com.brby.yisu/update"
    private val storagePermissionRequestCode = 4701
    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> saveToDownloads(call, result)
                "deleteDownload" -> deleteDownload(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath").orEmpty()
        val rawFileName = call.argument<String>("fileName").orEmpty()
        val mimeType = call.argument<String>("mimeType")
            ?: "application/octet-stream"
        val source = File(sourcePath)
        val fileName = File(rawFileName).name
        if (!source.isFile || fileName.isBlank()) {
            result.error("invalid_download", "下载临时文件无效。", null)
            return
        }

        val request = PendingSave(source, fileName, mimeType, result)
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingSave != null) {
                result.error("download_busy", "已有安装包正在保存。", null)
                return
            }
            pendingSave = request
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storagePermissionRequestCode
            )
            return
        }
        performSave(request)
    }

    private fun performSave(request: PendingSave) {
        Thread {
            try {
                val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(request)
                } else {
                    saveToLegacyDownloads(request)
                }
                runOnUiThread { request.result.success(saved) }
            } catch (error: Exception) {
                runOnUiThread {
                    request.result.error(
                        "save_download_failed",
                        error.message ?: "无法保存到 Download 文件夹。",
                        null
                    )
                }
            }
        }.start()
    }

    private fun saveWithMediaStore(request: PendingSave): Map<String, String> {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, request.fileName)
            put(MediaStore.Downloads.MIME_TYPE, request.mimeType)
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values
        ) ?: throw IllegalStateException("系统未能创建 Download 文件。")
        try {
            resolver.openOutputStream(uri, "w").use { output ->
                requireNotNull(output) { "系统无法写入 Download 文件。" }
                FileInputStream(request.source).use { input ->
                    input.copyTo(output)
                }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return mapOf(
                "location" to "Download/${request.fileName}",
                "uri" to uri.toString()
            )
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyDownloads(request: PendingSave): Map<String, String> {
        val directory = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建 Download 文件夹。")
        }
        val target = File(directory, request.fileName)
        if (target.exists() && !target.delete()) {
            throw IllegalStateException("无法替换旧安装包。")
        }
        FileInputStream(request.source).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return mapOf(
            "location" to "Download/${request.fileName}",
            "path" to target.absolutePath
        )
    }

    private fun deleteDownload(call: MethodCall, result: MethodChannel.Result) {
        val rawUri = call.argument<String>("uri").orEmpty()
        if (!rawUri.startsWith("content://")) {
            result.success(false)
            return
        }
        Thread {
            val deleted = try {
                applicationContext.contentResolver.delete(
                    android.net.Uri.parse(rawUri),
                    null,
                    null
                ) >= 0
            } catch (_: Exception) {
                false
            }
            runOnUiThread { result.success(deleted) }
        }.start()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != storagePermissionRequestCode) return
        val request = pendingSave ?: return
        pendingSave = null
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            performSave(request)
        } else {
            request.result.error(
                "storage_permission_denied",
                "未获得存储权限，无法保存到 Download 文件夹。",
                null
            )
        }
    }

    private data class PendingSave(
        val source: File,
        val fileName: String,
        val mimeType: String,
        val result: MethodChannel.Result
    )
}
