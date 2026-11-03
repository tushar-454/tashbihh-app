# Tasbih Counter — Native Flutter

An offline Flutter implementation of [tushar-454/tasbihh](https://github.com/tushar-454/tasbihh), preserving its prayer schedules, all 11 Dhikr entries, streak rules, Custom Mode, settings and navy/gold visual identity.

Android synchronizes local prayer times at local midnight while open, or on the
next launch/resume. Today's saved schedule avoids repeat API calls. Failed
refreshes keep the last compatible saved times; without saved data, the existing
JSON schedule applies. See [prayer-time behavior and implementation](docs/prayer-times.md).

On Android, **Backup/Restore** connects Google Drive, automatically restores an
existing private backup, and backs up immediately on subsequent taps. It also
requests one latest backup whenever the app closes or goes to the background,
when completing every prayer's daily requirement increases the streak, and when
a failed daily requirement drops a streak to zero.
There is no periodic backup schedule. Interrupted uploads remain pending for the
next startup/resume. Close-time uploads are best effort because Android may stop
the process. Reset Everything coordinates local and cloud deletion. See
[backup behavior, recovery, and device checks](docs/google-drive-backup.md).

```sh
flutter pub get
flutter run -d emulator-5554  # Android
flutter run -d chrome         # Web
flutter run -d linux          # Desktop
```

```sh
flutter analyze
flutter test
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Release builds require your
existing private signing key; there is no debug-key fallback. Follow the
[Android release setup](docs/android-releases.md) to configure local signing and
automatic signed APK releases on app-related pushes to `main`.

For an offline Web release, run `flutter build web --release`, then `python3 tool/prepare_web_offline.py`, and serve `build/web` over HTTPS or localhost. Native apps work offline immediately; Web requires one initial cached load.

Read the [source audit](docs/source-audit.md), [implementation and platform notes](docs/implementation-notes.md), [feature checklist](docs/feature-checklist.md), [asset report](docs/missing-assets.md), and [visual comparison](docs/validation/README.md).
