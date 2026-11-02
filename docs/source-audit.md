# Source audit

Audited every file in `/home/tushar/Documents/code/tasbih_web` (read only): index.html, styles.css, script.js, config.js, project-overview.md, readme.md, both SVGs, manifest.webmanifest, sw.js. GitHub comparison hashes are recorded in reference-hashes.json. The Flutter target is the existing `tashbihh` package in the current workspace; all six generated platform folders are preserved.

## Screens, controls, and interactions

- Full-height prayer-gradient canvas; gold Arabic `بِسْمِ اللَّهِ`, spaced TASBIH COUNTER subtitle.
- Arabic Dua selector with transliteration, target, red cross / green check; anchored scrolling list of eligible entries, Arabic, full transliteration and meaning, target, selection highlight, completion status. Streak badge with flame and integer.
- Center count and progress ring. Classic: target-count dots at radius 130 in 320-unit viewBox, radii 5 (<=34), 4 (<=50), 3 otherwise; active dots use HSL(i/target*360,80%,60%). Modern: radius 118, width 16, gold round-cap arc. Center <=140px, 2px border, Amiri bold count. Count caps at target; no automatic Dua advancement.
- Completion radial glow keyed to prayer; center pulse 520ms. Entry fade/slide 220ms, prayer background transition 550ms, chevron 150ms.
- Five bottom prayer tiles, selected gold, disabled opacity .45, ended-window inset red border. Only current prayer selectable while a window is open in Prayer Mode. Outside windows all selectable for review. Custom Mode all selectable; prayer selection continues to control theme and Dua menu.
- Gear at bottom right opens anchored settings, outside click closes menus. Settings: vibration 0–100ms step5 default40; app-mode button displays destination mode; Custom target slider 10–1000 step10 default100; style displays destination Classic/Modern, default Classic; Full Screen/Exit Full Screen; Reset all data.
- Custom Mode retains selected prayer/Dua text and menu; displayed target uses custom target; completion tick still represents prayer progress. Independent count, no time restrictions, cap at target; reducing target clamps count.
- Double-click center resets custom count, or incomplete selected prayer Dua; completed prayer Duas cannot be reset this way. Prayer reset has no time eligibility check.
- Reset confirmation title `Reset all data?`, exact description `This will permanently remove saved progress, daily prayer counts, and streak data.`, Cancel/Delete actions. Outside/Escape dismiss. Delete restores settings, prayer progress, custom progress and streak; fullscreen is session state.
- Source center has role=button/tabindex and aria-label but no keyboard handler. Native implementation supplies keyboard and screen-reader activation. Dialogs have modal/focus semantics; selectors expose selected/disabled states.

## Exact fixed local schedule

Start inclusive, end exclusive, minute precision; no geolocation/astronomy/backend.

| Prayer | Arabic | Icon | Start | End |
|---|---|---|---|---|
| Fajr | الفجر | 🌅 | 04:45 | 06:00 |
| Dhuhr | الظهر | ☀️ | 12:00 | 15:00 |
| Asr | العصر | 🌤️ | 16:45 | 18:00 |
| Maghrib | المغرب | 🌇 | 18:45 | 20:00 |
| Isha | العشاء | 🌙 | 20:30 | 22:00 |

Counting requires selected==active prayer, non-null active window, unlocked prayer and count<target. Clock heartbeat runs every 30s and auto-selects active prayer; date rollover clears all prayer counts, completions and per-prayer selected Duas, preserving selected prayer, custom count/target, settings and applicable streak. Native checks clock before each interaction and on resume as well to avoid stale eligibility.

## Complete Dhikr coverage

Exact Unicode text, meanings, order and eligible prayer IDs are copied mechanically from config.js into assets/data/config.json (11 entries; no expanded recitation text invented).

| ID | Transliteration | Target | Eligibility |
|---|---|---:|---|
| subhanallah | SubhanAllah | 33 | all |
| alhamdulillah | Alhamdulillah | 33 | all |
| allahuakbar | Allahu Akbar | 34 | all |
| lailahaillallah | La ilaha illallah | 100 | fajr, maghrib, isha |
| astaghfirullah | Astaghfirullah | 33 | all |
| lahawla | La hawla wa la quwwata illa billah | 33 | fajr, isha |
| ayatulkursi | Ayatul Kursi | 1 | all |
| sayyidulistighfar | Sayyidul Istighfar | 3 | fajr, maghrib |
| durood | Allahumma salli ala Muhammad | 10 | all |
| subhanallahi_wabihamdihi | SubhanAllahi wa bihamdihi | 100 | fajr, isha |
| allahumma_inni_asalukal_afiyah | Allah Humma Inni As'alukal Afiyah | 10 | all |

Counts are independent per prayer and Dua. Completion is count>=target; completed IDs are appended on reaching target and validated against counts on load.

## Streak rules from actual JavaScript

`didMeetDailyStreakRequirement`: all five prayers have >=3 completed IDs. `applyStreakIfEligible`: if requirement passes and lastStreakDate!=today, increments current streak and stores today. There is **no explicit Isha time/one-Isha-Dua gate** in this function. Normal interaction necessarily reaches Isha before all five can qualify. Every same-day roll-forward also evaluates it. On a date change retain streak only if lastStreakDate==old progress date AND the source local-midnight dayDiff is exactly 1; otherwise zero. Preserve last successful date even on break. Reset prayer data first, then evaluate. Native reproduces these conditions. The native port also preserves the exact local-midnight elapsed-millisecond division and Math.floor behavior. In a DST timezone, a 23-hour spring-forward day therefore has dayDiff 0 and breaks a streak, as in the source; a 25-hour autumn day has dayDiff 1. A 47-hour two-date gap across spring-forward also floors to1; that source quirk is retained. Asia/Dhaka has no DST, so this quirk does not affect its normal schedule.

## Design tokens and layout

HSL tokens: background(220,20%,8%), foreground(45,30%,90%), card(220,15%,12%), card-soft(220,15%,18%,.65), primary(45,80%,55%), muted(220,10%,62%), accent(45,60%,45%), border(220,12%,22%), danger(0,72%,62%).

180° three-stop gradients: Fajr [(220,40%,12%),(210,50%,25%),(35,40%,30%)]; Dhuhr [(45,50%,20%),(40,40%,15%),(35,30%,10%)]; Asr [(35,50%,18%),(30,45%,14%),(25,35%,10%)]; Maghrib [(15,50%,18%),(340,30%,15%),(260,25%,12%)]; Isha [(240,30%,8%),(230,25%,10%),(220,20%,8%)].

Fonts: Google Fonts Amiri regular/bold (Arabic, count) and IBM Plex Sans Arabic regular/medium/semibold (body). Bismillah26.4px; subtitle10.24px letterspace2.048px; selector Arabic16px, meta11.2px; count clamp41.6–57.6px; meaning11.68px italic; prayer label9.92px.

Canvas padding24px vertical/8px horizontal (top16px <=440px). Header top6.4px. Selector max460px with16px side insets, gap8px, corner13.6px. Streak width96px (88px <=440px). Counter min(88vw,360px); center min(38vw,140px). Prayer row max400px, side16px/bottom9.6px, gap7.2px, min tile56px, radius12.8px. Settings right16/bottom22.4 (10.4/16 narrow), button40px, panel245px, padding14.4px, maxheight min(76vh,620px). Dialog max380px/radius14.4px/padding16px, blur4px overlay. Native minimum48px control hit areas and scroll fallback for short windows/large accessibility text.

## Assets and metadata

Only original SVG icons plus Google Fonts; no remote photos, illustration, icon library or audio. Original icon gradients/navy/gold and text33 retained, rasterized for native launchers. Maskable file has opaque full square background. Manifest: Tasbih Counter / Tasbih, theme/background #151a26, standalone, portrait. Fonts bundled offline with OFL licenses. SVG assets copied verbatim; no SVG rendering dependency needed for CustomPainter counter.

## Meaningful discrepancies / native decisions

1. README prayer times differ from config.js; config wins (table above).
2. Docs mention Isha time gate and streak reset-to1; JS uses all-five completion condition, increments and handles breaks during daily rollover. JS wins.
3. project-overview claims progress key `tasbih-progress-v2` and vibration toggle; config uses `tasbih-progress`, HTML only intensity (0 disables). Fresh Flutter storage uses its own versioned snapshot; no browser data migration/import.
4. Source stops click propagation on center without attaching an increment listener; background clicks count but center single taps do not. This conflicts with documented center-button workflow and the user's explicit requirement. Native center **and unobstructed background** count, while controls/menu dismissal never count.
5. JS validates custom targets down to1 but HTML permits10–1000 step10. Native user-facing slider preserves10–1000 step10; defensive stored-state normalization follows source bounds1–1000.
6. sw.js includes missing all_in_one.html, potentially breaking atomic shell caching; irrelevant to installed native offline operation. Font CDN requests are not explicitly precached in source; native bundles fonts.
7. Source has no explicit center blocked style; prayer tiles carry disabled/locked visuals. Native preserves these and adds an accessible reason/tooltip to the center, without redesigning it.
8. Native uses gesture arbitration on the center: a single tap waits for the double-tap interval and counts once; a double tap resets without an increment. Unobstructed background taps count immediately. Completed prayer Duas remain protected. Screen readers get an explicit reset action because their double-tap activation convention must count once.
