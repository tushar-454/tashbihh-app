# Tasbih Counter — Native Flutter

An offline Flutter implementation of [tushar-454/tasbihh](https://github.com/tushar-454/tasbihh), preserving its prayer schedules, all 11 Dhikr entries, streak rules, Custom Mode, settings and navy/gold visual identity.

Android automatically synchronizes local prayer times once per day while the app
is open, with persistent caching and the existing JSON schedule as its offline
fallback. See [prayer-time behavior and implementation](docs/prayer-times.md).

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

APK: `build/app/outputs/flutter-apk/app-release.apk`. The starter's debug signing key is used for the installable release build; set up your private key before store distribution.

For an offline Web release, run `flutter build web --release`, then `python3 tool/prepare_web_offline.py`, and serve `build/web` over HTTPS or localhost. Native apps work offline immediately; Web requires one initial cached load.

Read the [source audit](docs/source-audit.md), [implementation and platform notes](docs/implementation-notes.md), [feature checklist](docs/feature-checklist.md), [asset report](docs/missing-assets.md), and [visual comparison](docs/validation/README.md).
