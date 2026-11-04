package com.example.tashbihh

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import java.time.Instant
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33, 34])
class PrayerNotificationsTest {
    private lateinit var app: Application
    private lateinit var oldZone: TimeZone
    private val minute = 60_000L
    private val midnight = Instant.parse("2030-01-01T00:00:00Z").toEpochMilli()
    private val prefix = "flutter.tasbih.notifications."
    private val progressKey = "flutter.tasbih.native.snapshot.v1"
    private fun prefs() = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private fun pending() = JSONObject(prefs().getString(prefix + "pending", "{}")!!)
    private fun consumed() = JSONObject(prefs().getString(prefix + "consumed", "{}")!!)
    private fun notifications() = app.getSystemService(NotificationManager::class.java).activeNotifications

    @Before fun setup() {
        app = RuntimeEnvironment.getApplication()
        oldZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        prefs().edit().clear().commit()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        PrayerNotifications.configure(app, plan().toString(), midnight)
        PrayerNotifications.writeProgress(app, snapshot().toString(), false, now = midnight)
    }

    @After fun cleanup() { TimeZone.setDefault(oldZone) }

    private fun plan(date: String = "2030-01-01", base: Long = midnight, lateIsha: Boolean = false): JSONObject {
        val windows = JSONArray()
        PrayerNotificationPolicy.prayers.forEachIndexed { i, prayer ->
            windows.put(JSONObject().put("id", prayer)
                .put("start", base + (i * 120 + 300) * minute)
                .put("end", base + (i * 120 + 410) * minute))
        }
        val day = JSONObject().put("date", date).put("dayStart", base).put("dayEnd", base + 1440 * minute)
            .put("windows", windows).put("ishaStart", base + (if (lateIsha) 22 else 19) * 60 * minute)
            .put("ishaEnd", base + 1440 * minute)
        val targets = JSONObject()
        PrayerNotificationPolicy.prayers.forEach { targets.put(it, JSONObject("{\"a\":1,\"b\":1,\"c\":1,\"d\":1}")) }
        return JSONObject().put("version", 1).put("zone", "UTC").put("days", JSONArray().put(day)).put("targets", targets)
    }

    private fun snapshot(n: Int = 0, date: String = "2030-01-01", account: String = ""): JSONObject {
        val prayers = JSONObject()
        PrayerNotificationPolicy.prayers.forEach { prayer ->
            val values = JSONObject()
            listOf("a", "b", "c", "d").take(n).forEach { values.put(it, 1) }
            prayers.put(prayer, JSONObject().put("counts", values))
        }
        return JSONObject().put("state", JSONObject().put("date", date).put("prayers", prayers))
            .put("cloud", JSONObject().put("accountId", account))
    }

    @Test fun `first install defaults enabled and inexact fallback schedules eleven`() {
        val state = PrayerNotifications.status(app)
        assertEquals(true, state["enabled"])
        assertEquals(true, state["allowed"])
        assertEquals(false, state["exact"])
        assertFalse(PrayerNotifications.hasPrompted(app))
        PrayerNotifications.markPrompted(app)
        assertTrue(PrayerNotifications.hasPrompted(app))
        assertEquals(11, pending().length())
        assertTrue(pending().keys().asSequence().all { pending().getString(it).endsWith("/false") })
    }

    @Test fun `disable persists cancels every alarm and reenable reconciles once`() {
        PrayerNotifications.setEnabled(app, false, now = midnight)
        assertEquals(false, PrayerNotifications.status(app)["enabled"])
        assertEquals(0, pending().length())
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(0, pending().length())
        PrayerNotifications.setEnabled(app, true, now = midnight)
        assertEquals(11, pending().length())
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(11, pending().length())
    }

    @Test fun `denied revoked and restored permission change actual eligibility`() {
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(false, PrayerNotifications.status(app)["allowed"])
        assertEquals(0, pending().length())
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(11, pending().length())
    }

    @Test fun `exact access grant replaces inexact signatures without duplicate IDs`() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(11, pending().length())
        assertTrue(pending().keys().asSequence().all { pending().getString(it).endsWith("/true") })
        assertEquals(22, shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.size)
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(11, shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms.size)
    }

    @Test fun `saved progress independently cancels and restores future prayer alarms`() {
        val data = snapshot()
        data.getJSONObject("state").getJSONObject("prayers").put("dhuhr", snapshot(3).getJSONObject("state").getJSONObject("prayers").getJSONObject("dhuhr"))
        PrayerNotifications.writeProgress(app, data.toString(), false, now = midnight)
        assertEquals(9, pending().length())
        assertFalse(pending().has("2030-01-01/dhuhr/5"))
        assertTrue(pending().has("2030-01-01/asr/5"))
        PrayerNotifications.writeProgress(app, snapshot(2).toString(), false, now = midnight)
        assertEquals(11, pending().length())
        assertEquals(snapshot(2).toString(), PrayerNotifications.readProgress(app))
    }

    @Test fun `delivery reads latest committed counts rather than scheduled text`() {
        PrayerNotifications.writeProgress(app, snapshot(2).toString(), false, now = midnight)
        val key = "2030-01-01/fajr/30"
        PrayerNotifications.deliver(app, key, midnight + 380 * minute)
        assertEquals(1, notifications().size)
        assertTrue(notifications().single().notification.extras.getString("android.text")!!.contains("2 of 3"))
        PrayerNotifications.deliver(app, key, midnight + 381 * minute)
        PrayerNotifications.reconcile(app, force = true, now = midnight + 381 * minute)
        assertEquals(1, notifications().size)
        assertTrue(consumed().has(key))
        assertFalse(pending().has(key))
    }

    @Test fun `completion at delivery suppresses reminders even with a queued old intent`() {
        PrayerNotifications.writeProgress(app, snapshot(3).toString(), false, now = midnight)
        PrayerNotifications.deliver(app, "2030-01-01/fajr/30", midnight + 380 * minute)
        assertTrue(notifications().isEmpty())
    }

    @Test fun `summary uses latest counts and survives restart reboot and duplicate events`() {
        PrayerNotifications.writeProgress(app, snapshot(3).toString(), false, now = midnight)
        val key = "2030-01-01/summary/0"
        PrayerNotifications.deliver(app, key, midnight + 22 * 60 * minute)
        assertTrue(notifications().single().notification.extras.getString("android.title")!!.contains("All Goals Completed"))
        PrayerNotifications.configure(app, plan().toString(), midnight + 22 * 60 * minute)
        PrayerNotifications.reconcile(app, force = true, now = midnight + 22 * 60 * minute)
        PrayerNotifications.deliver(app, key, midnight + 22 * 60 * minute + 1)
        assertEquals(1, notifications().size)
        assertTrue(consumed().has(key))
    }

    @Test fun `midnight summary retains previous date progress when next day resets`() {
        PrayerNotifications.configure(app, plan(lateIsha = true).toString(), midnight)
        PrayerNotifications.writeProgress(app, snapshot(3).toString(), false, now = midnight)
        val tomorrow = midnight + 1440 * minute
        PrayerNotifications.writeProgress(app, snapshot(date = "2030-01-02").toString(), false, now = midnight)
        PrayerNotifications.configure(app, plan("2030-01-02", tomorrow).toString(), tomorrow)
        PrayerNotifications.deliver(app, "2030-01-01/summary/0", tomorrow + 60 * minute)
        val text = notifications().single().notification.extras.getString("android.text")!!
        assertTrue(text.contains("2030-01-01"))
        assertTrue(text.contains("all 5"))
    }

    @Test fun `restore reset and account switch remove previous dated derived progress`() {
        PrayerNotifications.writeProgress(app, snapshot(3).toString(), false, now = midnight)
        val tomorrow = snapshot(date = "2030-01-02")
        PrayerNotifications.writeProgress(app, tomorrow.toString(), true, now = midnight)
        assertFalse(JSONObject(prefs().getString(prefix + "history", "{}")!!).has("2030-01-01"))
        PrayerNotifications.writeProgress(app, snapshot(3, account = "new-account").toString(), false, now = midnight)
        assertFalse(JSONObject(prefs().getString(prefix + "history", "{}")!!).has("2030-01-02"))
        PrayerNotifications.writeProgress(app, snapshot().toString(), true, now = midnight)
        // A replacement dated after the exported schedule invalidates that plan.
        // A new foreground schedule is required before alarms can be reinitialized.
        PrayerNotifications.configure(app, plan().toString(), midnight)
        assertEquals(11, pending().length())
        assertTrue(notifications().isEmpty())
    }

    @Test fun `timezone mismatch cancels stale instants and corrected zone reconciles`() {
        TimeZone.setDefault(TimeZone.getTimeZone("Asia/Dhaka"))
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(0, pending().length())
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(11, pending().length())
    }

    @Test fun `schedule refresh changes pending instants and clock forward drops past events`() {
        val updated = plan()
        val window = updated.getJSONArray("days").getJSONObject(0).getJSONArray("windows").getJSONObject(0)
        window.put("end", midnight + 420 * minute)
        PrayerNotifications.configure(app, updated.toString(), midnight)
        assertTrue(pending().getString("2030-01-01/fajr/30").startsWith("${midnight + 390 * minute}/"))
        PrayerNotifications.reconcile(app, force = true, now = midnight + 421 * minute)
        assertFalse(pending().has("2030-01-01/fajr/30"))
        assertTrue(pending().has("2030-01-01/dhuhr/30"))
    }

    @Test fun `corrupt or unavailable schedule does not create alarms`() {
        prefs().edit().putString(prefix + "plan", "broken").commit()
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(0, pending().length())
    }

    @Test fun `OS notification and channel blocking are respected`() {
        val manager = app.getSystemService(NotificationManager::class.java)
        shadowOf(manager).setNotificationsEnabled(false)
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(false, PrayerNotifications.status(app)["allowed"])
        assertEquals(0, pending().length())
        shadowOf(manager).setNotificationsEnabled(true)
        manager.createNotificationChannel(NotificationChannel("prayer_goals_v1", "Prayer goals", NotificationManager.IMPORTANCE_NONE))
        PrayerNotifications.reconcile(app, now = midnight)
        assertEquals(false, PrayerNotifications.status(app)["allowed"])
        assertEquals(0, pending().length())
    }

    @Test fun `erased previous day summary cannot deliver from removed history`() {
        PrayerNotifications.configure(app, plan(lateIsha = true).toString(), midnight)
        PrayerNotifications.writeProgress(app, snapshot(3).toString(), false, now = midnight)
        PrayerNotifications.writeProgress(app, snapshot(date = "2030-01-02").toString(), true, now = midnight)
        PrayerNotifications.deliver(app, "2030-01-01/summary/0", midnight + 25 * 60 * minute)
        assertTrue(notifications().isEmpty())
    }

    @Test fun `reboot or package replacement rearms lost alarms without duplicating identities`() {
        val alarmManager = app.getSystemService(AlarmManager::class.java)
        val shadow = shadowOf(alarmManager)
        val existing = shadow.scheduledAlarms.toList()
        existing.forEach { alarm -> alarm.operation?.let { alarmManager.cancel(it) } }
        assertEquals(0, shadow.scheduledAlarms.size)
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(11, shadow.scheduledAlarms.size)
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(11, shadow.scheduledAlarms.size)
    }

    @Test fun `stale reminders and summaries after horizon expiry never post`() {
        PrayerNotifications.deliver(app, "2030-01-01/fajr/30", midnight + 1440 * minute)
        PrayerNotifications.deliver(app, "2030-01-01/summary/0", midnight + 2 * 1440 * minute)
        PrayerNotifications.reconcile(app, force = true, now = midnight + 8 * 1440 * minute)
        assertTrue(notifications().isEmpty())
        assertEquals(0, pending().length())
    }

    @Test fun `last scheduled day summary can deliver after the horizon midnight`() {
        PrayerNotifications.configure(app, plan(lateIsha = true).toString(), midnight)
        PrayerNotifications.writeProgress(app, snapshot(2).toString(), false, now = midnight)
        PrayerNotifications.deliver(app, "2030-01-01/summary/0", midnight + 25 * 60 * minute)
        assertEquals(1, notifications().size)
        assertTrue(notifications().single().notification.extras.getString("android.text")!!.contains("2030-01-01"))
    }

    @Test fun `actual deliveries remain bounded at eleven per local date`() {
        val ledger = JSONObject()
        repeat(11) { ledger.put("2030-01-01/event/$it", "2030-01-01") }
        prefs().edit().putString(prefix + "consumed", ledger.toString()).commit()
        PrayerNotifications.deliver(app, "2030-01-01/fajr/30", midnight + 380 * minute)
        assertTrue(notifications().isEmpty())
    }

    @Test fun `explicit opt out survives restore reset account switch and restart`() {
        PrayerNotifications.setEnabled(app, false, now = midnight)
        PrayerNotifications.writeProgress(app, snapshot(2).toString(), true, now = midnight)
        PrayerNotifications.writeProgress(app, snapshot(account = "different-account").toString(), true, now = midnight)
        PrayerNotifications.configure(app, plan().toString(), midnight)
        PrayerNotifications.reconcile(app, force = true, now = midnight)
        assertEquals(false, PrayerNotifications.status(app)["enabled"])
        assertEquals(0, pending().length())
        PrayerNotifications.deliver(app, "2030-01-01/fajr/30", midnight + 380 * minute)
        assertTrue(notifications().isEmpty())
    }

    @Test fun `notification tap preserves prayer identity without modifying progress`() {
        val before = PrayerNotifications.readProgress(app)
        PrayerNotifications.deliver(app, "2030-01-01/fajr/30", midnight + 380 * minute)
        val intent = shadowOf(notifications().single().notification.contentIntent).savedIntent
        assertEquals("fajr", intent.getStringExtra("prayerTap"))
        assertTrue(intent.action!!.contains("2030-01-01/fajr/30"))
        assertNull(intent.data)
        assertEquals(before, PrayerNotifications.readProgress(app))
    }
}
