package com.example.tashbihh

import android.content.Context
import org.json.JSONObject

/** Reads the same bundled catalog as Flutter; receivers work after process death
 * and boot without a Flutter engine or device-locale dependent Android resources. */
internal object PrayerTranslations {
    private var catalog: JSONObject? = null
    @Synchronized private fun catalog(context: Context): JSONObject {
        return catalog ?: context.assets.open("flutter_assets/assets/localization/translations.json")
            .bufferedReader().use { JSONObject(it.readText()) }.also { catalog = it }
    }

    fun forContext(context: Context): PrayerText {
        val all = catalog(context)
        val snapshot = runCatching {
            JSONObject(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.tasbih.native.snapshot.v1", "{}") ?: "{}")
        }.getOrDefault(JSONObject())
        val language = if (snapshot.optJSONObject("settings")?.optString("app_language") == "bn") "bn" else "en"
        return { key, args ->
            val entry = all.optJSONObject(key)
            val template = entry?.optString(language)?.takeIf { it.isNotEmpty() }
                ?: entry?.optString("en")?.takeIf { it.isNotEmpty() } ?: key
            Regex("\\{([a-zA-Z_][a-zA-Z_0-9]*)\\}").replace(template) { match ->
                args[match.groupValues[1]]?.toString() ?: match.value
            }
        }
    }
}
