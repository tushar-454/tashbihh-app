package com.example.tashbihh

internal typealias PrayerText = (String, Map<String, Any>) -> String

internal data class PrayerWindow(val prayer: String, val start: Long, val end: Long)
internal data class PrayerDay(
    val date: String, val start: Long, val end: Long,
    val windows: List<PrayerWindow>, val ishaStart: Long, val ishaEnd: Long,
)
internal data class PrayerEvent(
    val date: String, val prayer: String, val offset: Int,
    val at: Long, val start: Long, val end: Long,
) {
    val key: String get() = "$date/$prayer/$offset"
}
internal data class PrayerMessage(val title: String, val body: String, val details: String = body)

/** All eligibility and wording live here, shared by reconciliation and delivery. */
internal object PrayerNotificationPolicy {
    const val GOAL = 3
    const val MINUTE = 60_000L
    val prayers = listOf("fajr", "dhuhr", "asr", "maghrib", "isha")

    fun events(days: List<PrayerDay>): List<PrayerEvent> = days.flatMap { day ->
        day.windows.flatMap { window ->
            listOf(30, 5).mapNotNull { offset ->
                val at = window.end - offset * MINUTE
                if (at < window.start || at >= window.end) null
                else PrayerEvent(day.date, window.prayer, offset, at, window.start, window.end)
            }
        } + PrayerEvent(day.date, "summary", 0, day.ishaStart + 180 * MINUTE, day.ishaStart, day.ishaEnd)
    }

    fun pending(event: PrayerEvent, now: Long, counts: Map<String, Int>, consumed: Set<String>): Boolean =
        event.at > now && event.key !in consumed &&
            (event.prayer == "summary" || counts.getOrDefault(event.prayer, 0) < GOAL)

    fun deliverable(event: PrayerEvent, now: Long, counts: Map<String, Int>, consumed: Set<String>): Boolean =
        event.key !in consumed && now >= event.at &&
            if (event.prayer == "summary") now < event.at + 6 * 60 * MINUTE
            else now < event.end && now >= event.start && counts.getOrDefault(event.prayer, 0) < GOAL

    fun message(event: PrayerEvent, now: Long, counts: Map<String, Int>, text: PrayerText): PrayerMessage {
        if (event.prayer == "summary") return summary(event, now, counts, text)
        val name = text("prayer_${event.prayer}", emptyMap())
        val count = counts.getOrDefault(event.prayer, 0).coerceAtLeast(0)
        // Late inexact delivery still reports the actual remaining duration.
        val left = ((event.end - now + MINUTE - 1) / MINUTE).coerceAtLeast(1)
        val title = text(if (event.offset == 5) "notification_ending" else "notification_reminder", mapOf("prayer" to name))
        val invitation = text("invitation_${event.prayer}", emptyMap())
        return PrayerMessage(title, text("notification_body", mapOf("prayer" to name, "minutes" to left, "count" to count, "invitation" to invitation)))
    }

    private fun summary(event: PrayerEvent, now: Long, counts: Map<String, Int>, text: PrayerText): PrayerMessage {
        val incomplete = prayers.filter { counts.getOrDefault(it, 0) < GOAL }
        val complete = 5 - incomplete.size
        val details = prayers.joinToString("\n") {
            val count = counts.getOrDefault(it, 0)
            text("summary_detail", mapOf("prayer" to text("prayer_$it", emptyMap()), "count" to count,
                "status" to text(if (count >= GOAL) "completed" else "incomplete", emptyMap())))
        }
        if (complete == 5) return PrayerMessage(
            text("summary_all_title", emptyMap()),
            text("summary_all_body", mapOf("date" to event.date)), details,
        )
        val encouragement = text(if ("isha" in incomplete && now >= event.start && now < event.end)
            "summary_isha" else "summary_encouragement", emptyMap())
        return PrayerMessage(
            text("summary_title", emptyMap()),
            text("summary_body", mapOf("date" to event.date, "complete" to complete, "incomplete" to incomplete.size,
                "prayers" to incomplete.joinToString { text("prayer_$it", emptyMap()) }, "encouragement" to encouragement)), details,
        )
    }
}
