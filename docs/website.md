# Tashbihh Counter website and GitHub Pages deployment

The informational website is in `website/`. It uses plain HTML and CSS, system fonts, and a copy of the existing app icon. It has no JavaScript, build step, sign-in, tracking, or external asset dependencies. The Flutter application is unchanged.

## Files and pages

| File | Purpose |
| --- | --- |
| `website/index.html` | App introduction, counting features, prayer times, offline behavior, optional Drive backup, source link, download placeholder, and support contact. |
| `website/privacy.html` | Local storage, location, Google authentication, Drive access, backup/restore/reset behavior, security, user choices, hosting, and contact. |
| `website/terms.html` | Acceptable use, prayer-time accuracy, backup availability, data loss, third-party services, changes, and contact. |
| `website/styles.css` | Shared responsive layout, typography, navigation, focus styles, and print styles. |
| `website/assets/app-icon.svg` | Copy of `assets/branding/icon.svg`; no new branding dependency. |
| `.github/workflows/deploy-website.yml` | Packages only `website/` and deploys its contents to Pages. |
| `docs/website.md` | Deployment instructions and source-based privacy review notes; not part of the published artifact. |

## Source review and privacy practices

No applicable `AGENTS.md` was found in the project or its ancestor directories during this implementation.

| Behavior | Evidence in the existing app |
| --- | --- |
| Prayer-specific dhikr counts, selected prayer/dhikr, completion, custom count/target, streak dates, historical restore record, and settings are stored locally. Custom Mode is a single adjustable counter, not named user-created counter collections. | `lib/core/models/app_state.dart`, `lib/core/storage/progress_repository.dart`, `lib/features/counter/counter_controller.dart`, `lib/features/settings/settings_panel.dart` |
| SharedPreferences stores progress/settings and connected account ID/email, timestamps, change fingerprint, and pending reset state. | `lib/core/storage/progress_repository.dart`, `lib/core/backup/cloud_backup_coordinator.dart` |
| Android asks for coarse/fine location and makes bounded one-shot foreground readings; no background location permission or continuous stream is used. Coordinates are rounded to three decimal places. | `android/app/src/main/AndroidManifest.xml`, `lib/core/prayer/prayer_location.dart`, `lib/core/prayer/prayer_times.dart` |
| HTTPS requests to AlAdhan include rounded latitude/longitude, date, method, and school. Device time zone is used locally for validation, not explicitly sent as an API parameter. | `lib/core/prayer/aladhan_client.dart`, `lib/core/prayer/prayer_times.dart` |
| A daily schedule caches rounded coordinates, times, date, method/school, time zones, UTC offset, and sync time separately from progress. The prompt record is a separate preference. Neither is in the backup. | `lib/core/prayer/prayer_times_repository.dart`, `lib/core/prayer/prayer_times.dart`, `lib/main.dart`, `lib/core/backup/backup_service.dart` |
| Prayer sync runs when needed while foregrounded, on startup/resume and clock/date/time-zone changes, with limited retries. Valid daily caches are reused; configured times are the fallback. Same-day movement within the same time zone need not trigger refresh. | `lib/core/prayer/prayer_time_sync.dart`, `lib/features/counter/counter_screen.dart` |
| Google authentication is optional and uses only `drive.appdata` as the explicit Drive authorization scope. The SDK handles identity and tokens; the app stores account ID/email locally. | `lib/core/backup/google_drive_backup.dart` |
| Drive REST operations are restricted to the private `appDataFolder` and the app's `tasbihh_backup.json` filename. Backup contents are state/settings plus format, version, timestamps, and checksum; local cloud metadata and location cache are excluded. | `lib/core/backup/google_drive_backup.dart`, `lib/core/backup/backup_service.dart`, `lib/core/backup/cloud_backup_format.dart` |
| Connecting a valid backup account automatically replaces local state/settings. If none exists, local progress is kept and a first upload is created. Switching does not delete the previous account's backup or revoke its grant. | `lib/core/backup/cloud_backup_coordinator.dart`, `lib/core/backup/google_drive_backup.dart` |
| Connected Backup/Restore taps attempt an immediate upload before the account dialog. Automatic changed-data backup uses a 12-hour due interval, foreground checks every five minutes, and an overdue startup/resume check. No headless/background backup worker is implemented. | `lib/features/counter/counter_screen.dart`, `lib/core/backup/cloud_backup_coordinator.dart`, `lib/core/backup/cloud_ports.dart` |
| Reset marks durable pending intent, deletes/verifies the connected account's matching backup files, then resets progress/settings/connection metadata. Network/auth/deletion failure can retain progress and leave reset pending. A later local write failure can happen after cloud deletion. | `lib/core/backup/cloud_backup_coordinator.dart`, `lib/core/backup/google_drive_backup.dart`, `lib/features/counter/counter_controller.dart` |
| Reset does not clear the separate location/schedule cache or prompt marker, revoke Google authorization, or delete old accounts' backups. Clear Android app storage to remove all local preferences; manage cloud data separately. | Same reset sources, plus `lib/main.dart` and `lib/core/prayer/prayer_times_repository.dart` |
| App preferences and backups have no app-level encryption. HTTPS protects API transport; base64 and SHA-256 checksums do not provide encryption. | `lib/core/storage/progress_repository.dart`, `lib/core/backup/cloud_backup_format.dart`, API clients |
| No advertising, analytics, crash reporting SDK, or developer collection endpoint was found in the reviewed app code/dependencies. Manifest permissions are internet, vibration, and coarse/fine location; standard Android automatic app backup is disabled. | `lib/`, `pubspec.yaml`, `pubspec.lock`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/example/tashbihh/MainActivity.kt` |

## Developer review before production

The pages describe the inspected implementation. Source review cannot establish all operational or legal facts:

- Confirm the final distributed APK still matches these practices and has no newly added SDKs, services, permissions, or data flows. Third-party SDK and provider logging, storage protections, retention, and operational practices are not established by this repository. No AlAdhan retention promise is made.
- Review and adopt the Google API Services User Data Policy / Limited Use commitment in the policy. The implementation's narrow backup use supports the description, but this is not an independent compliance certification or Google approval. Confirm support-email handling/retention and any actual off-app practices, intended audience, and jurisdiction-specific obligations; these cannot be inferred from code. No business identity, address, jurisdiction, or child-directed status was invented.
- Effective dates are November 3, 2026. Adjust to the actual policy effective date if launching later and keep privacy/terms dates accurate when revising content.
- The installed app currently calls itself **Tasbih Counter**, while the requested public website is **Tashbihh Counter**. Confirm consistent app/consent-screen/Play listing branding before OAuth review. The policy notes the current Android settings label so instructions remain usable.
- No in-app privacy/terms link was found in the current settings UI. Google expects accessible in-product privacy disclosures as well as consent-screen URLs; review this before production. Adding app links was outside this website-only change.
- The homepage source URL is derived from `origin`: `https://github.com/tushar-454/tashbihh-app`. Ensure the repository is publicly accessible. The Android release link is explicitly marked **Download link: coming soon**. Replace that paragraph in `website/index.html` with a verified release link when ready; do not advertise an unpublished download.
- The website and workflow have been prepared locally. Actual GitHub deployment, Search Console ownership verification, Google console settings, production APK behavior, and OAuth review must be completed in your accounts.

## Push this repository

The current branch is `main` and `origin` is already configured as `https://github.com/tushar-454/tashbihh-app.git`. There is no need to initialize Git again or add a duplicate remote.

1. Sign in to GitHub and ensure `tushar-454/tashbihh-app` exists. If it does not, create an **empty public repository** with that name; do not initialize it with another README or history. Public repositories support Pages on GitHub Free. If it already exists, preserve its history.
2. From a terminal, run:

   ```sh
   cd /home/tushar/development/tashbihh
   git remote -v
   git status --short
   git add website/ .github/workflows/deploy-website.yml docs/website.md
   git diff --cached --stat
   git commit -m "Add Tashbihh Counter website and Pages deployment"
   git push -u origin main
   ```

   Use your normal GitHub authentication if prompted. These commands stage only this website change. Do not force-push if Git reports divergent remote history; fetch and reconcile the histories first. If you intentionally choose another repository, change `origin`, update the homepage source link, and derive the Pages URLs from the new owner/repository.

## Enable GitHub Pages through Actions

1. Open `https://github.com/tushar-454/tashbihh-app/settings/pages`.
2. Under **Build and deployment → Source**, select **GitHub Actions**. Do not select “Deploy from a branch”; this workflow handles the arbitrary `website/` folder.
3. Under **Settings → Actions → General**, ensure Actions is enabled and the official `actions/checkout`, `actions/configure-pages`, `actions/upload-pages-artifact`, and `actions/deploy-pages` actions are permitted. No personal access token or repository secret is needed; the workflow declares scoped permissions for GitHub's built-in job token. There is no need to grant all workflows broad write permissions in repository settings.
4. Under **Settings → Environments → github-pages**, allow deployments from `main` if branch restrictions are configured. GitHub may create this environment on first deployment. Satisfy any protection rules you intentionally use.
5. Open **Actions → Deploy website to GitHub Pages → Run workflow**, choose `main`, and run it. This is useful after first enabling Pages if the push-triggered run failed before Pages was enabled. Later pushes changing `website/**` or this workflow on `main` deploy automatically. A docs-only or Flutter-only change does not trigger this workflow; manual runs are restricted to `main` by the job condition.
6. Wait for both **package** and **deploy** to succeed. Open the deployment URL reported by the `github-pages` environment. Confirm the homepage, privacy, and terms load over HTTPS without signing in. Keep **Enforce HTTPS** enabled if that control is available; default `github.io` sites use HTTPS.

The package job checks out the website, reads Pages configuration, and uploads **only `website/`**. The deploy job has only `pages: write` and `id-token: write`. There is no Flutter compilation, Node/npm setup, framework build, custom backend, or credential file. Official Actions may use their own bundled runtimes. The existing manual macOS app-build workflow is unchanged.

GitHub documents the setup in [Using custom workflows with GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Expected public URLs and Google Auth Platform branding

These URLs are derived from the current remote, **not a claim that deployment has occurred**:

| Google Auth Platform → Branding field | URL to paste after successful deployment |
| --- | --- |
| Application home page | `https://tushar-454.github.io/tashbihh-app/` |
| Application privacy policy link | `https://tushar-454.github.io/tashbihh-app/privacy.html` |
| Application terms of service link | `https://tushar-454.github.io/tashbihh-app/terms.html` |

Use **Tashbihh Counter** as the requested app name and `tusharimran.olw@gmail.com` as the support email, subject to Google's requirement that the selected support email be eligible for the project. Review app-name consistency with the installed Android label as noted above. Confirm the Google Drive API is enabled and **Data Access** matches the implemented `https://www.googleapis.com/auth/drive.appdata` scope. Google currently documents this as a non-sensitive scope; that does not itself grant branding approval. The static website needs no OAuth client, Google Sign-In integration, authorized JavaScript origins, or redirect endpoint.

See Google's [brand-verification requirements](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification) and [Drive scope documentation](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

## Domain verification considerations

GitHub Pages hosting and Google OAuth branding approval are separate. Google's brand-verification guidance requires ownership verification for authorized top private domains associated with your branding links. Publishing public HTML alone does not prove this requirement is satisfied.

1. In Google Auth Platform → Branding → **Authorized domains**, use the domain Google accepts for your hosted site, potentially `tushar-454.github.io`, without `https://` or `/tashbihh-app/`. Do not claim to own `github.com` or the shared `github.io` parent. Confirm acceptance in your project's console rather than assuming it from these files.
2. Use a Google account that is an Owner or Editor of the Cloud project for Search Console verification. A URL-prefix property for `https://tushar-454.github.io/tashbihh-app/` can be verified using the exact HTML file supplied by Search Console: put that file in `website/`, commit/push it, wait for deployment, then complete verification. If Google supplies a meta-tag method instead, use the exact real tag in `website/index.html`; no fabricated verification tag has been added.
3. URL-prefix ownership verification may not satisfy the authorized-domain verification Google requires for your particular hosted domain. If Google rejects the shared hosting domain or requires ownership proof that cannot be supplied for it, use a custom domain you control. GitHub Pages can still host the site for free: configure **Settings → Pages → Custom domain**, add GitHub's required DNS records, verify the registrable domain in Search Console with DNS, and update all three branding URLs to the same verified domain. All website-relative links work on a custom domain too. For Actions publication, configure the custom domain in repository settings; a `CNAME` file alone does not configure it.
4. Review the consent screen and verification status after changing URLs/domains. Only Google can determine whether a particular configuration meets its current requirements; neither these pages nor deployment establishes production approval.

No Search Console verification token is known yet, so none is included. Keep any real verification file/tag in place after verification.

## Local preview and validation

There is no installation or build step. To preview only the public site:

```sh
python3 -m http.server 8080 --directory website --bind 127.0.0.1
```

Open `http://127.0.0.1:8080/`. To check project-site subpaths, serve the repository root instead and open `/website/`; all internal URLs are relative and resolve inside that prefix.

Validation completed for this change:

- All three pages passed HTML structure, metadata, heading hierarchy, duplicate ID, local asset/link, and anchor checks. The SVG parsed successfully and matches the existing app icon.
- Installed Chrome passed all three pages at 320, 375, 768, and 1280 pixels (12 page/viewport combinations), plus increased text size at 200%, without horizontal overflow. Keyboard skip links and every internal link/fragment resolved under `/website/`.
- Browser checks found no page errors, external asset/network requests, cookies, or local/session storage created by the website. Desktop and mobile homepage screenshots were visually inspected.
- Ten designed foreground/background text pairs exceeded WCAG AA's 4.5:1 normal-text threshold; the lowest measured ratio was 5.75:1. This is a focused accessibility check, not a full accessibility certification.
- Workflow YAML, main-branch/path triggers, manual-run condition, job dependency/environment, artifact directory, official actions, and per-job permissions passed structural checks. The published directory contains only three HTML pages, CSS, and the SVG icon. No credential-like content was found there in a targeted pattern scan.
- Existing tracked Flutter/app files remained unchanged. No Flutter build was needed for this static-site-only change.

Static and browser checks do not execute a real GitHub Actions deployment or Google OAuth verification. The HTML checks were structural checks with a parser and browser, not a full Nu/W3C conformance validation.
