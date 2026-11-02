package com.example.tashbihh

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private val io = Executors.newSingleThreadExecutor()
    private var clockSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private val clockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            clockSink?.success(intent?.action ?: "clock")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasbih/backup_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "save" && call.method != "open") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Another document operation is in progress.", null)
                } else {
                    val saving = call.method == "save"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (saving && (bytes == null || bytes.size > MAX_BYTES)) {
                        result.error("size", "Backup must be at most 1 MB.", null)
                        return@setMethodCallHandler
                    }
                    pending = result
                    exportBytes = bytes
                    try {
                        val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("application/json")
                        if (saving) intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename"))
                        startActivityForResult(intent, if (saving) SAVE_DOCUMENT else OPEN_DOCUMENT)
                    } catch (e: Exception) {
                        finishDocument(error = "Could not open the Android document picker. ${e.localizedMessage}")
                    }
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "tasbih/local_clock")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { clockSink = events }
                override fun onCancel(arguments: Any?) { clockSink = null }
            })
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_DATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(clockReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(clockReceiver, filter)
        receiverRegistered = true
    }

    override fun onStop() {
        if (receiverRegistered) unregisterReceiver(clockReceiver)
        receiverRegistered = false
        super.onStop()
    }

    @Deprecated("Activity result bridge used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_DOCUMENT && requestCode != OPEN_DOCUMENT) return
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK) {
            finishDocument(if (requestCode == SAVE_DOCUMENT) false else null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            finishDocument(error = "The document provider returned no file.")
            return
        }
        val bytes = exportBytes
        io.execute {
            try {
                val value: Any? = if (requestCode == SAVE_DOCUMENT) {
                    contentResolver.openOutputStream(uri, "wt")?.use { stream ->
                        stream.write(bytes ?: error("Missing backup data"))
                        stream.flush()
                    } ?: error("Could not write this document")
                    true
                } else {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count == -1) break
                            if (output.size() + count > MAX_BYTES) error("Backup is too large. Maximum size is 1 MB.")
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    } ?: error("Could not read this document")
                }
                runOnUiThread { finishDocument(value) }
            } catch (e: Exception) {
                runOnUiThread { finishDocument(error = "Document operation failed. ${e.localizedMessage}") }
            }
        }
    }

    private fun finishDocument(value: Any? = null, error: String? = null) {
        val result = pending
        pending = null
        exportBytes = null
        if (error != null) result?.error("document", error, null) else result?.success(value)
    }

    override fun onDestroy() {
        finishDocument(error = "Document operation interrupted. Please try again.")
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        const val MAX_BYTES = 1024 * 1024
        const val SAVE_DOCUMENT = 7301
        const val OPEN_DOCUMENT = 7302
    }
}
