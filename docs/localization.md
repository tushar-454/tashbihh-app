# English and Bangla localization

The app supports `en` and `bn` only. New installations and upgrades without a language preference start in English, regardless of the device locale. The compact `EN` / `বাং` badges in the Settings header update the current screen, dialogs, messages, semantics, and theme without replacing the navigation tree. Existing scroll and counter state remain in place.

## Catalog and messages

`assets/localization/translations.json` is the translation source. Each named key has `en` and `bn` entries. `AppLocalizations.load()` decodes the bundled catalog once before `runApp`; Flutter's localization delegate reuses it. Widgets use `context.tr('key', {'argument': value})`. Missing or empty Bangla entries fall back to English; unknown keys remain visible as keys.

Service messages use `AppMessage` keys and arguments, including nested messages, and resolve when displayed. A saved cloud status or visible snackbar therefore changes language without another network operation. Existing English diagnostic getters remain compatible with the prior tests and service API. Flutter's built-in Material, Widgets, and Cupertino localization delegates supply framework-owned text.

Android notification receivers read the same bundled JSON once per process and obtain the current language from the saved snapshot at delivery. Alarm eligibility, delivery ledgers, counter reconciliation, notification channel identity, and scheduling remain unchanged. Android permission dialogs, Google's account picker, and notification typography are controlled by their respective platforms.

## Persistence and Drive compatibility

The existing SharedPreferences snapshot key, `tasbih.native.snapshot.v1`, remains the commit unit. The language is stored in `settings.app_language`, with supported values `en` and `bn`. Android uses the existing synchronized `AndroidProgressStore`; other platforms use `PreferencesStore`. Keeping language in the snapshot avoids a second preference write that could disagree with a restored counter snapshot.

Both backup schema versions remain `1`. New backups include `data.settings.app_language` inside the existing payload and checksummed Drive envelope. A backup without the field preserves the current local language. A present but invalid value falls back to English. A failed restore does not activate its language or counters. Counter reset and Reset Everything preserve the current language.

Language changes use the existing serialized progress write queue. Repeated taps on the selected badge do nothing. The next normal close, explicit, streak, or daily-reset backup includes the language; language selection introduces no new network schedule or Google sign-in prompts.

## Fonts

English uses `Comfortaa`; Bangla uses `KohinoorBangla`. Theme and explicit button/tooltip styles share bundled fallbacks for Bangla, Latin, Arabic, symbols, and emoji. Arabic religious text is preserved. Existing sizes, weights, colors, and spacing remain in place.

Both required font paths exist. English uses the supplied `assets/fonts/Comfortaa.ttf` directly; Bangla uses `assets/fonts/KohinoorBangla.ttf`. The duplicate Comfortaa font file was removed. No font download or substitute was used.

## Changed files

Created: `assets/localization/translations.json`, `lib/core/localization/app_localizations.dart`, Android `PrayerTranslations.kt`, `test/flutter_test_config.dart`, `test/localization_test.dart`, and this document.

Updated: `pubspec.yaml` / lockfile; `lib/main.dart`; app/theme; settings, counter, prayer and dhikr widgets; counter controller and settings model; existing backup serializer/coordinator/Drive errors; prayer schedule and location/sync messages; storage errors; Dart and Android notification messages; Android policy/notification tests; existing visual and integration tests.

Release versioning, application ID, signing, certificates, OAuth scopes, Drive filename, and GitHub Actions configuration are unchanged.

## Verification

`test/localization_test.dart` covers defaults, saved preferences, placeholders and English fallback, locale/font switching, badge semantics, counter preservation, duplicate taps, storage failures, Drive export/restore compatibility, and real-font layouts at 280, 390, 844, and 1440 pixels with normal and 200% text scaling. Existing suites cover counter calculations, prayer synchronization, account switching, reset, and automatic backup behavior. Android tests additionally verify background notification wording and preference fallback.

Verified in this environment: `flutter pub get`, formatting, and the final `flutter build apk --debug` succeeded; `flutter analyze` reported no issues; `flutter test --concurrency=1` passed all 261 tests; Android `:app:testDebugUnitTest` passed all 57 tests; and the Android emulator integration workflow passed, including language/font switching, disk reload, and reset preservation. Real bundled fonts were used in widget layout tests and inspected in Android screenshots. Drive serialization, restoration, and account switching were exercised through the existing fake-account tests. A live signed-in Google Drive round-trip was not performed, and no extra Google sign-in prompt was opened.
