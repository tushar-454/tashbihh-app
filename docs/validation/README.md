# Visual and runtime validation

`source-*.png` were captured from the **actual live website** with Chrome/Playwright, using Asia/Dhaka and a deterministic clock. `flutter-*.png` were captured from native Flutter widgets with the bundled source fonts. The source and Flutter fixture clocks agree: default11:00, Fajr counting05:00, blocked/review07:00, 2 November2026. See source-fixtures.json.

At390×844, the refined header, selector and counter align closely with the source: original font sizes, colors, center diameter140, ring343.2, SVG-equivalent dot radius/positions, bottom prayer row and fixed settings gear. Native text rasterization and control fonts have small engine differences. Settings keep the source's compact panel, destination labels and original slider blue. Native controls support touch, keyboard and accessibility.

| State | Live source | Flutter |
|---|---|---|
| Default | [source](source-default.png) | [native](flutter-default.png) |
| Dua list | [source](source-dua-menu.png) | [native](flutter-dua-menu.png) |
| Classic partial | [source](source-classic-partial.png) | [native](flutter-classic-partial.png) |
| Target completed | [source](source-completed.png) | [native](flutter-completed.png) |
| Selected blocked prayer | [source](source-blocked-prayer.png) | [native](flutter-blocked-prayer.png) |
| Settings | [source](source-settings.png) | [native](flutter-settings.png) |
| Custom Mode | [source](source-custom.png) | [native](flutter-custom.png) |
| Modern partial | [source](source-modern-partial.png) | [native](flutter-modern-partial.png) |
| Reset confirmation | [source](source-reset.png) | [native](flutter-reset.png) |
| Narrow280×568 | [source](source-narrow.png) | [native](flutter-narrow.png) |
| Large1440×900 | [source](source-large.png) | [native](flutter-large.png) |
| Landscape844×390 | Source has no special landscape breakpoint | [native scroll fallback](flutter-landscape.png) |

`chrome-*.png` and chrome-results.json describe the compiled Flutter Web build running in actual Chrome, including offline reload. They use the current clock rather than the reference fixture. The browser script uses ordinary pointer input at the source-matched control positions and inspects only the new Flutter app snapshot to verify results, so double-tap recognition is tested as a pointer gesture. Screen-reader activation has a separate explicit reset action.

Android integration captures are named `android-*.png`. Platform run/build results are recorded in implementation-notes.md. Screenshots represent real captures; no missing platform screenshots were fabricated.
