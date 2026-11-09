package com.pdfreaderonly.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "app.docreader/intent"
    private var sharedFileUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW && intent.type?.startsWith("application/pdf") == true) {
            val uri = intent.data
            if (uri != null) {
                try {
                    // Copy to cache dir to provide standard file path to Flutter
                    val fileName = "shared_document_${System.currentTimeMillis()}.pdf"
                    val file = File(cacheDir, fileName)
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(file).use { output ->
                            input.copyTo(output)
                        }
                    }
                    sharedFileUri = file.absolutePath
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedPdf") {
                result.success(sharedFileUri)
                sharedFileUri = null // clear after reading
            } else {
                result.notImplemented()
            }
        }
    }
}
