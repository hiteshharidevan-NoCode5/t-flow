package com.reader.tflow.t_flow

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.reader.tflow.t_flow/content_resolver"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getFilePathFromContentUri") {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    try {
                        val uri = Uri.parse(uriString)
                        val inputStream = contentResolver.openInputStream(uri)
                        val tempFile = File(cacheDir, "temp_external_doc.pdf")
                        val outputStream = FileOutputStream(tempFile)
                        inputStream?.use { input ->
                            outputStream.use { output ->
                                input.copyTo(output)
                            }
                        }
                        result.success(tempFile.absolutePath)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                } else {
                    result.error("INVALID_URI", "URI string was null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
