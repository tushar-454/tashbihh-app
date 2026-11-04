package com.example.tashbihh

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
    fun label(prayer: String) = prayer.replaceFirstChar { it.uppercase() }

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

    fun message(event: PrayerEvent, now: Long, counts: Map<String, Int>): PrayerMessage {
        if (event.prayer == "summary") return summary(event, now, counts)
        val name = label(event.prayer)
        val count = counts.getOrDefault(event.prayer, 0).coerceAtLeast(0)
        // Inexact alarms may arrive late. State the actual remaining duration,
        // rather than repeating the originally requested 30/5 minute offset.
        val left = ((event.end - now + MINUTE - 1) / MINUTE).coerceAtLeast(1)
        val title = if (event.offset == 5) "⏰ $name Ending Soon" else "🌿 $name Reminder"
        val invitation = when (prayers.indexOf(event.prayer)) {
            0 -> "Begin with a peaceful moment of remembrance."
            1 -> "Take a gentle pause for dhikr."
            2 -> "A few peaceful moments can make a difference."
            3 -> "Make time for a little remembrance this evening."
            else -> "Close this prayer window with a moment of dhikr."
        }
        return PrayerMessage(title, "$name ends in about $left minutes. You've completed $count of 3 tasbih goals. $invitation")
    }

    private fun summary(event: PrayerEvent, now: Long, counts: Map<String, Int>): PrayerMessage {
        val incomplete = prayers.filter { counts.getOrDefault(it, 0) < GOAL }
        val complete = 5 - incomplete.size
        val details = prayers.joinToString("\n") {
            val count = counts.getOrDefault(it, 0)
            "${label(it)}: $count/3 — ${if (count >= GOAL) "Completed" else "Incomplete"}"
        }
        if (complete == 5) return PrayerMessage(
            "✨ Alhamdulillah! All Goals Completed",
            "You completed your tasbih goal for all 5 prayers on ${event.date}! May Allah bless your consistency. Keep going tomorrow!",
            details,
        )
        val encouragement = if ("isha" in incomplete && now >= event.start && now < event.end)
            "Isha is still available; a peaceful moment can help you reach its goal."
        else "Every effort matters. May tomorrow bring more moments of remembrance."
        return PrayerMessage(
            "🌙 Your Daily Tashbihh Summary",
            "For ${event.date}: $complete of 5 prayers completed; ${incomplete.size} incomplete (${incomplete.joinToString { label(it) }}). $encouragement",
            details,
        )
    }
}
