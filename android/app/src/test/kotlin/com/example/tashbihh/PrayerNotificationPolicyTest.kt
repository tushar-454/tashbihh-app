package com.example.tashbihh

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PrayerNotificationPolicyTest {
    private fun message(event: PrayerEvent, now: Long, counts: Map<String, Int>) =
        PrayerNotificationPolicy.message(event, now, counts, PrayerTranslations.forContext(RuntimeEnvironment.getApplication()))
    private val minute = PrayerNotificationPolicy.MINUTE
    private val window = PrayerWindow("dhuhr", 12 * 60 * minute, 16 * 60 * minute)
    private val day = PrayerDay("2026-11-04", 0, 1440 * minute, listOf(window), 19 * 60 * minute, 1440 * minute)
    private val reminders = PrayerNotificationPolicy.events(listOf(day)).filter { it.prayer == "dhuhr" }
    private val summary = PrayerNotificationPolicy.events(listOf(day)).last()
    private fun counts(n: Int) = mapOf("dhuhr" to n)

    @Test fun `zero one two remain eligible and three or more cancel both`() {
        for (n in 0..10) for (event in reminders) {
            assertEquals(n < 3, PrayerNotificationPolicy.pending(event, window.start, counts(n), emptySet()))
            assertEquals(n < 3, PrayerNotificationPolicy.deliverable(event, event.at, counts(n), emptySet()))
        }
    }

    @Test fun `third completion before between and after offsets only cancels future`() {
        for (now in listOf(15 * 60 * minute, 15 * 60 * minute + 40 * minute, 16 * 60 * minute)) {
            assertTrue(reminders.none { PrayerNotificationPolicy.pending(it, now, counts(3), emptySet()) })
            assertEquals(reminders.count { it.at > now }, reminders.count {
                PrayerNotificationPolicy.pending(it, now, counts(2), emptySet())
            })
        }
    }

    @Test fun `five prayers are independent and decrease can restore future events`() {
        val all = PrayerNotificationPolicy.prayers.flatMap { prayer -> reminders.map { it.copy(prayer = prayer) } }
        val values = PrayerNotificationPolicy.prayers.associateWith { if (it == "dhuhr") 3 else 1 }
        assertEquals(8, all.count { PrayerNotificationPolicy.pending(it, window.start, values, emptySet()) })
        assertEquals(10, all.count { PrayerNotificationPolicy.pending(it, window.start, values + ("dhuhr" to 2), emptySet()) })
    }

    @Test fun `expired and already due events are never newly scheduled`() {
        for (event in reminders) {
            assertFalse(PrayerNotificationPolicy.pending(event, event.at, counts(0), emptySet()))
            assertFalse(PrayerNotificationPolicy.deliverable(event, event.end, counts(0), emptySet()))
            assertFalse(PrayerNotificationPolicy.deliverable(event, event.at - 1, counts(0), emptySet()))
        }
    }

    @Test fun `short windows skip invalid offsets`() {
        val short = day.copy(windows = listOf(window.copy(end = window.start + 10 * minute)))
        assertEquals(listOf(5), PrayerNotificationPolicy.events(listOf(short)).filter { it.prayer == "dhuhr" }.map { it.offset })
        val tiny = short.copy(windows = listOf(window.copy(end = window.start + 4 * minute)))
        assertTrue(PrayerNotificationPolicy.events(listOf(tiny)).none { it.prayer == "dhuhr" })
    }

    @Test fun `refreshed end replaces instant but preserves deterministic event identity`() {
        val changed = PrayerNotificationPolicy.events(listOf(day.copy(windows = listOf(window.copy(end = window.end + 10 * minute)))))
        assertEquals(reminders[0].key, changed[0].key)
        assertEquals(reminders[0].at + 10 * minute, changed[0].at)
        assertNotEquals(reminders[0].key, reminders[1].key)
        assertNotEquals(reminders[0].key, reminders[0].copy(date = "2026-11-05").key)
    }

    @Test fun `all six completion levels produce truthful respectful summaries`() {
        for (n in 0..5) {
            val values = PrayerNotificationPolicy.prayers.mapIndexed { i, p -> p to if (i < n) 3 else 2 }.toMap()
            val text = message(summary, summary.at, values)
            if (n == 5) assertTrue(text.title.contains("All Goals Completed"))
            else {
                assertTrue(text.body.contains("$n of 5"))
                assertTrue(text.body.contains("${5 - n} incomplete"))
            }
            assertEquals(5, text.details.lines().size)
            assertTrue(text.body.contains(day.date))
        }
    }

    @Test fun `only incomplete active Isha receives an invitation`() {
        assertTrue(message(summary, summary.at, counts(0)).body.contains("Isha is still available"))
        assertFalse(message(summary, summary.end, counts(0)).body.contains("still available"))
        assertFalse(message(summary, summary.at, mapOf("isha" to 3)).body.contains("still available"))
        assertFalse(message(summary, summary.at, counts(0)).body.contains("finish Dhuhr"))
    }

    @Test fun `summary plus three elapsed hours retains its source date after midnight`() {
        val lateDay = day.copy(ishaStart = 22 * 60 * minute)
        val late = PrayerNotificationPolicy.events(listOf(lateDay)).last()
        assertEquals(25 * 60 * minute, late.at)
        assertEquals(day.date, late.date)
        assertFalse(message(late, late.at, counts(0)).body.contains("still available"))
    }

    @Test fun `delivery reads supplied latest progress and consumed ledger suppresses duplicates`() {
        val first = message(summary, summary.at, emptyMap())
        val latest = message(summary, summary.at, PrayerNotificationPolicy.prayers.associateWith { 3 })
        assertNotEquals(first.title, latest.title)
        assertFalse(PrayerNotificationPolicy.deliverable(summary, summary.at, counts(0), setOf(summary.key)))
        assertFalse(PrayerNotificationPolicy.pending(summary, 0, counts(0), setOf(summary.key)))
    }

    @Test fun `late reminders describe actual remaining minutes and stale summary is dropped`() {
        val event = reminders[0]
        assertTrue(message(event, event.at + 20 * minute, counts(1)).body.contains("about 10 minutes"))
        assertFalse(PrayerNotificationPolicy.deliverable(summary, summary.at + 6 * 60 * minute, counts(0), emptySet()))
    }
}
