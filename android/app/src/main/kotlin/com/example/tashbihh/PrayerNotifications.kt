package com.example.tashbihh

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.TimeZone
import java.util.Date
import java.util.Locale
import java.text.SimpleDateFormat
import java.util.concurrent.Executors

/** Short, serialized disk/alarm work. No Flutter engine, network, service or polling. */
internal object PrayerNotifications {
    val executor = Executors.newSingleThreadExecutor()
    private const val PREFIX = "flutter.tasbih.notifications."
    private const val PROGRESS = "flutter.tasbih.native.snapshot.v1"
    private const val CHANNEL = "prayer_goals_v1"
    private const val TAG = "prayer_goals/"
    private fun prefs(context: Context) = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private fun json(context: Context, key: String) = runCatching {
        JSONObject(prefs(context).getString(PREFIX + key, "{}") ?: "{}")
    }.getOrDefault(JSONObject())
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    private fun ensureChannel(context: Context) {
        val text = PrayerTranslations.forContext(context)
        if (Build.VERSION.SDK_INT >= 26) manager(context).createNotificationChannel(
            NotificationChannel(CHANNEL, text("notification_channel", emptyMap()), NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = text("notification_channel_description", emptyMap())
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }

    fun status(context: Context): Map<String, Boolean> {
        ensureChannel(context)
        val permission = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channelAllowed = Build.VERSION.SDK_INT < 26 || manager(context).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
        return mapOf(
            "enabled" to prefs(context).getBoolean(PREFIX + "enabled", true),
            "allowed" to (permission && channelAllowed && manager(context).areNotificationsEnabled()),
            "exact" to (Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()),
        )
    }

    fun hasPrompted(context: Context) = prefs(context).getBoolean(PREFIX + "prompted", false)
    fun markPrompted(context: Context) {
        check(prefs(context).edit().putBoolean(PREFIX + "prompted", true).commit())
    }

    @Synchronized fun setEnabled(context: Context, enabled: Boolean, now: Long = System.currentTimeMillis()) {
        check(prefs(context).edit().putBoolean(PREFIX + "enabled", enabled).commit())
        if (!enabled) cancelVisible(context)
        reconcile(context, now = now)
    }

    @Synchronized fun readProgress(context: Context): String? = prefs(context).getString(PROGRESS, null)

    @Synchronized fun writeProgress(context: Context, raw: String, replacement: Boolean, now: Long = System.currentTimeMillis()) {
        val next = JSONObject(raw)
        val old = runCatching { JSONObject(readProgress(context) ?: "{}") }.getOrDefault(JSONObject())
        val switched = old.optJSONObject("cloud")?.optString("accountId", "") != next.optJSONObject("cloud")?.optString("accountId", "")
        val clear = replacement || switched
        val history = if (clear) JSONObject() else json(context, "history")
        val state = next.getJSONObject("state")
        history.put(state.getString("date"), JSONObject(countsFromState(state, json(context, "plan"))))
        // Only a bounded derived count archive, never identity/authentication data.
        val dates = history.keys().asSequence().sortedDescending().toList()
        dates.drop(8).forEach { history.remove(it) }
        val editor = prefs(context).edit().putString(PROGRESS, raw)
            .putString(PREFIX + "history", history.toString())
        if (clear) {
            val plan = json(context, "plan")
            val days = plan.optJSONArray("days") ?: JSONArray()
            val remaining = JSONArray()
            for (i in 0 until days.length()) {
                val day = days.getJSONObject(i)
                if (day.getString("date") >= state.getString("date")) remaining.put(day)
            }
            plan.put("days", remaining)
            editor.putString(PREFIX + "plan", plan.toString())
        }
        check(editor.commit()) { "Progress could not be saved" }
        // A scheduling failure must not report a successfully committed counter
        // write as failed. The next resume/clock/boot event retries reconciliation.
        runCatching {
            if (clear) cancelVisible(context)
            reconcile(context, now = now)
        }
    }

    @Synchronized fun configure(context: Context, raw: String, now: Long = System.currentTimeMillis()) {
        val plan = JSONObject(raw)
        require(plan.getInt("version") == 1 && plan.getJSONArray("days").length() <= 7)
        require(plan.getString("zone") in TimeZone.getAvailableIDs())
        // Preserve a pending previous-date summary across midnight and restarts.
        val days = plan.getJSONArray("days")
        val firstDate = days.getJSONObject(0).getString("date")
        val oldDays = json(context, "plan").optJSONArray("days") ?: JSONArray()
        if (json(context, "plan").optString("zone") == plan.getString("zone")) {
            for (i in 0 until oldDays.length()) {
                val day = oldDays.getJSONObject(i)
                if (day.getString("date") < firstDate && day.getLong("ishaStart") + 9 * 60 * PrayerNotificationPolicy.MINUTE > now) days.put(day)
            }
        }
        val history = json(context, "history")
        val state = runCatching { JSONObject(readProgress(context) ?: "{}").optJSONObject("state") }.getOrNull()
        if (state != null) history.put(state.getString("date"), JSONObject(countsFromState(state, plan)))
        check(prefs(context).edit().putString(PREFIX + "plan", plan.toString())
            .putString(PREFIX + "history", history.toString()).commit())
        reconcile(context, now = now)
    }

    private fun days(plan: JSONObject): List<PrayerDay> {
        val days = plan.optJSONArray("days") ?: return emptyList()
        return (0 until days.length()).map { i ->
            val d = days.getJSONObject(i)
            val windows = d.getJSONArray("windows")
            PrayerDay(d.getString("date"), d.getLong("dayStart"), d.getLong("dayEnd"),
                (0 until windows.length()).map { j -> windows.getJSONObject(j).let {
                    PrayerWindow(it.getString("id"), it.getLong("start"), it.getLong("end"))
                } }, d.getLong("ishaStart"), d.getLong("ishaEnd"))
        }
    }

    private fun countsFromState(state: JSONObject, plan: JSONObject): Map<String, Int> {
        val targets = plan.optJSONObject("targets") ?: return emptyMap()
        val prayers = state.optJSONObject("prayers") ?: return emptyMap()
        return PrayerNotificationPolicy.prayers.associateWith { prayer ->
            val values = prayers.optJSONObject(prayer)?.optJSONObject("counts")
            val allowed = targets.optJSONObject(prayer)
            allowed?.keys()?.asSequence()?.count { id ->
                (values?.optInt(id, 0) ?: 0) >= allowed.getInt(id)
            } ?: 0
        }
    }

    private fun counts(context: Context, date: String, plan: JSONObject): Map<String, Int> {
        val state = runCatching { JSONObject(readProgress(context) ?: "{}").optJSONObject("state") }.getOrNull()
        if (state?.optString("date") == date) return countsFromState(state, plan)
        val archived = json(context, "history").optJSONObject(date)
        return PrayerNotificationPolicy.prayers.associateWith { archived?.optInt(it, 0) ?: 0 }
    }

    private fun pendingIntent(context: Context, key: String, backup: Boolean = false): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = "com.example.tashbihh.PRAYER_ALARM"
            data = Uri.parse("tasbih://${if (backup) "prayer-alarm-backup" else "prayer-alarm"}/$key")
            putExtra("key", key)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    @Synchronized fun reconcile(context: Context, force: Boolean = false, now: Long = System.currentTimeMillis()) {
        val plan = json(context, "plan")
        val status = status(context)
        val consumed = json(context, "consumed").keys().asSequence().toSet()
        val desired = JSONObject()
        val events = if (status["enabled"] == true && status["allowed"] == true && plan.optString("zone") == TimeZone.getDefault().id)
            PrayerNotificationPolicy.events(days(plan)) else emptyList()
        val old = json(context, "pending")
        val progress = events.map { it.date }.distinct().associateWith { counts(context, it, plan) }
        for (event in events) {
            if (!PrayerNotificationPolicy.pending(event, now, progress.getValue(event.date), consumed)) continue
            val signature = "${event.at}/${status["exact"]}"
            desired.put(event.key, signature)
            if (force || old.optString(event.key) != signature) {
                val alarm = pendingIntent(context, event.key)
                val backup = pendingIntent(context, event.key, backup = true)
                try {
                    if (status["exact"] == true) {
                        // Android kills the process and deletes exact alarms when
                        // special access is revoked, without a revocation broadcast.
                        // A paired inexact alarm survives that transition. Delivery
                        // is still at most once through the persisted event ledger.
                        alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, backup)
                        alarms(context).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, alarm)
                    } else {
                        alarms(context).cancel(backup)
                        backup.cancel()
                        alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, alarm)
                    }
                } catch (_: SecurityException) {
                    // Special access may be revoked between the check and call.
                    alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, event.at, alarm)
                }
            }
        }
        old.keys().asSequence().filter { !desired.has(it) }.forEach { key ->
            for (backup in listOf(false, true)) {
                val intent = pendingIntent(context, key, backup)
                alarms(context).cancel(intent)
                intent.cancel()
            }
        }
        check(prefs(context).edit().putString(PREFIX + "pending", desired.toString()).commit())
    }

    @Synchronized fun deliver(context: Context, key: String, now: Long = System.currentTimeMillis()) {
        val plan = json(context, "plan")
        val status = status(context)
        if (status["enabled"] != true || status["allowed"] != true || plan.optString("zone") != TimeZone.getDefault().id) return
        val event = PrayerNotificationPolicy.events(days(plan)).firstOrNull { it.key == key } ?: return
        val consumed = json(context, "consumed")
        val values = counts(context, event.date, plan)
        if (!PrayerNotificationPolicy.deliverable(event, now, values, consumed.keys().asSequence().toSet())) return
        val allDays = days(plan)
        val localDate = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = TimeZone.getDefault()
        }.format(Date(now))
        // Also bound actual deliveries to eleven per local calendar day when a
        // delayed summary or changed schedule moves events across midnight.
        if (consumed.keys().asSequence().count { consumed.optString(it) == localDate } >= 11) return
        consumed.put(key, localDate)
        consumed.keys().asSequence().toList().filter { it.substringBefore('/') < allDays.minOf { d -> d.date } }.forEach { consumed.remove(it) }
        // Commit BEFORE posting: process death can lose a notification, but cannot
        // produce a duplicate on reboot/reschedule. Android has no atomic post+disk API.
        check(prefs(context).edit().putString(PREFIX + "consumed", consumed.toString()).commit())
        val text = PrayerNotificationPolicy.message(event, now, values, PrayerTranslations.forContext(context))
        val tap = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            // A unique action distinguishes PendingIntents without an Intent data
            // URI: Flutter would interpret that URI as an initial/deep-link route.
            // Navigation belongs exclusively to the consumed prayerTap payload.
            action = "com.example.tashbihh.PRAYER_TAP/$key"
            putExtra("prayerTap", event.prayer)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        manager(context).notify(TAG + key, 0, builder
            .setSmallIcon(R.drawable.ic_prayer_notification)
            .setContentTitle(text.title).setContentText(text.body)
            .setStyle(Notification.BigTextStyle().bigText(text.body + if (event.prayer == "summary") "\n\n${text.details}" else ""))
            .setContentIntent(tap).setAutoCancel(true).setShowWhen(true)
            .setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setDefaults(Notification.DEFAULT_ALL).build())
        reconcile(context, now = now)
    }

    private fun cancelVisible(context: Context) {
        manager(context).activeNotifications.filter { it.tag?.startsWith(TAG) == true }
            .forEach { manager(context).cancel(it.tag, it.id) }
    }
}

class PrayerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = goAsync()
        PrayerNotifications.executor.execute {
            try {
                val key = intent.getStringExtra("key")
                if (intent.action == "com.example.tashbihh.PRAYER_ALARM" && key != null) PrayerNotifications.deliver(context, key)
                else PrayerNotifications.reconcile(context, force = true)
            } catch (_: Exception) {
                // Corrupt/missing storage or OS denial must never crash a receiver.
                // Resume or another lifecycle event will reconcile valid state.
            } finally { result.finish() }
        }
    }
}
