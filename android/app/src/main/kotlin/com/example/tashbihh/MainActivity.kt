package com.example.tashbihh

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.Manifest
import android.provider.Settings
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var notificationPermission: MethodChannel.Result? = null
    private var notificationChannel: MethodChannel? = null
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
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasbih/prayer_notifications").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        val status = PrayerNotifications.status(this)
                        val firstRequest = !PrayerNotifications.hasPrompted(this) && status["enabled"] == true
                        if (firstRequest) PrayerNotifications.markPrompted(this)
                        if (Build.VERSION.SDK_INT >= 33 && status["enabled"] == true &&
                            firstRequest && status["allowed"] != true) {
                            try {
                                notificationPermission = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION)
                            } catch (_: Exception) {
                                notificationPermission = null
                                result.error("permission", "Notification permission unavailable", null)
                            }
                        } else notificationWork(result) {
                            PrayerNotifications.reconcile(this, force = true)
                            PrayerNotifications.status(this)
                        }
                    }
                    "status" -> notificationWork(result) {
                        PrayerNotifications.reconcile(this, force = true)
                        PrayerNotifications.status(this)
                    }
                    "readProgress" -> notificationWork(result) { PrayerNotifications.readProgress(this) }
                    "writeProgress" -> notificationWork(result) {
                        PrayerNotifications.writeProgress(this, call.argument<String>("value")!!, call.argument<Boolean>("replacement") == true)
                        null
                    }
                    "configure" -> notificationWork(result) { PrayerNotifications.configure(this, call.arguments as String); null }
                    "setEnabled" -> notificationWork(result) { PrayerNotifications.setEnabled(this, call.arguments == true); null }
                    "takeTap" -> {
                        val prayer = intent?.getStringExtra("prayerTap")
                        intent?.removeExtra("prayerTap")
                        result.success(prayer)
                    }
                    "settings", "alarmSettings" -> try {
                        val settingsIntent = if (call.method == "alarmSettings" && Build.VERSION.SDK_INT >= 31)
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                        else if (Build.VERSION.SDK_INT >= 26)
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        startActivity(settingsIntent)
                        result.success(null)
                    } catch (_: Exception) { result.error("settings", "Android settings unavailable", null) }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasbih/local_timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getTimeZone") result.success(TimeZone.getDefault().id)
                else result.notImplemented()
            }
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

    private fun notificationWork(result: MethodChannel.Result, work: () -> Any?) {
        PrayerNotifications.executor.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                runOnUiThread { result.error("notifications", "Could not update local notification state", null) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.hasExtra("prayerTap")) notificationChannel?.invokeMethod("tapAvailable", null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION) {
            val result = notificationPermission
            notificationPermission = null
            if (result != null) notificationWork(result) {
                PrayerNotifications.reconcile(this, force = true)
                PrayerNotifications.status(this)
            }
        }
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
        notificationPermission?.error("interrupted", "Permission request interrupted", null)
        notificationPermission = null
        notificationChannel?.setMethodCallHandler(null)
        finishDocument(error = "Document operation interrupted. Please try again.")
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        const val MAX_BYTES = 1024 * 1024
        const val SAVE_DOCUMENT = 7301
        const val OPEN_DOCUMENT = 7302
        const val NOTIFICATION_PERMISSION = 7303
    }
}
