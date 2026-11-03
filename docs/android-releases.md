# Automatic Android APK releases

The workflow `.github/workflows/android-release.yml` publishes a signed universal
APK when `main` contains unreleased Flutter/Android app changes. The Android
application ID stays **`com.example.tashbihh`**. App storage, permissions, backups,
and data formats are unchanged.

## One-time activation

### 1. Choose the permanent signing key

**If you have already distributed an APK, recover and reuse the keystore that
signed it.** Android requires the same signing certificate and a higher
versionCode for an update that preserves installed data. Keep an encrypted backup
of the keystore, alias, and passwords. Never regenerate the key for each build.

The project previously signed release builds with the local debug keystore. No
production keystore or `android/key.properties` was found in the project, and the
repository had no GitHub Releases when inspected. A fresh production key cannot
update an existing debug-signed installation. If those installations must update
in place, recover their original signing key first. Do not uninstall to work
around this: uninstalling removes local data. Any intentional switch to a new key
needs a separately planned backup/restore migration.

Only if no existing distributed signing identity must be preserved, generate one
production key **once**, outside the repository (Linux/macOS):

```sh
mkdir -p "$HOME/.android/release"
keytool -genkeypair -v -storetype JKS \
  -keystore "$HOME/.android/release/tashbihh-release.jks" \
  -alias tasbih -keyalg RSA -keysize 3072 -validity 10000
```

Enter the store password and certificate details interactively. Record the key
password too (pressing Enter at that prompt makes it the same as the store
password). Never commit this file or passwords. The workflow never generates a
signing key. Gradle also refuses release builds without signing configuration;
debug development builds continue to work normally.

### 2. Add five GitHub repository secrets

Open **Settings → Secrets and variables → Actions → Secrets → New repository
secret** in `tushar-454/tashbihh-app`:

| Exact secret name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the permanent keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore/store password |
| `ANDROID_KEY_ALIAS` | Signing key alias, `tasbih` for the command above |
| `ANDROID_KEY_PASSWORD` | Private key password, possibly the same as the store password |
| `ANDROID_SIGNING_CERT_SHA256` | SHA-256 **certificate** fingerprint of that signing key |

Encode the original keystore without printing it to a terminal log:

```sh
base64 < "$HOME/.android/release/tashbihh-release.jks" \
  | tr -d '\n' > /tmp/tashbihh-release.jks.base64
```

Paste that file's contents into `ANDROID_KEYSTORE_BASE64`, then remove the
temporary base64 file. Base64 is encoding, not encryption. GitHub CLI users can
avoid copying its contents:

```sh
gh secret set ANDROID_KEYSTORE_BASE64 \
  --repo tushar-454/tashbihh-app < /tmp/tashbihh-release.jks.base64
rm /tmp/tashbihh-release.jks.base64
```

Display the public certificate fingerprints (enter the password when prompted):

```sh
keytool -list -v \
  -keystore "$HOME/.android/release/tashbihh-release.jks" -alias tasbih
```

Copy the **SHA256** value into `ANDROID_SIGNING_CERT_SHA256`; colons are accepted.
This is the certificate fingerprint, not the hash of the keystore or APK file.
Register this certificate's **SHA1** with the Android OAuth client for
`com.example.tashbihh` in the existing Google Cloud project, so Google Drive
sign-in works in production. Keep the existing web client ID and debug OAuth
registration; see [Google Drive configuration](google-drive-backup.md).

### 3. Allow the workflow and account for older version codes

Enable Actions under **Settings → Actions → General**. If action restrictions are
enabled, allow `actions/checkout`, `actions/setup-java`, and
`subosito/flutter-action`, plus `actions/upload-artifact` for failed-verification
diagnostics. Repository/organization policy must permit this
workflow's explicit `contents: write` permission. The default repository token
setting can stay read-only; the release job requests the write permission it
needs. No personal access token or PR approval permission is needed. If tag
rulesets restrict `android-v*` creation, allow the release workflow's actor to
create these tags.

If APKs were distributed outside this workflow with a versionCode greater than
the `pubspec.yaml` build number, add repository **variable**
`ANDROID_VERSION_CODE_FLOOR` under **Secrets and variables → Actions → Variables**.
Set it to the highest versionCode already distributed. The next release will
exceed it. For an existing APK, inspect it with:

```sh
"$ANDROID_HOME/build-tools/36.0.0/aapt" dump badging /path/to/existing.apk
```

Read `versionCode` from the `package:` line. Currently `pubspec.yaml` is
`1.0.0+1`, so ordinary existing code-1 installations need no floor override.
The workflow also checks the previous release's actual APK certificate and code
before publishing, and fails with migration instructions if either is unsuitable.

### 4. Commit and push

Commit the workflow, helper, tests, signing Gradle change, ignore rules, and
documentation, then push to `main`. That app configuration change triggers the
first release. Watch **Actions → Android APK Release**. You can also use **Run
workflow** on `main` to bootstrap or retry; manual runs use the same change and
safety checks. Other branches cannot publish.

After success, **Releases** contains the versioned APK and its `.sha256` checksum.
Both the release notes and Actions job summary include the APK download link.
Users install the new APK as an update; installation is not forced remotely.

## Change detection and versioning

A small planning job runs on each `main` push. It compares the full git tree
against the last published `android-v*` release. This avoids GitHub path-filter
file limits and catches app changes from failed or replaced pending runs. If a
docs-only push follows an unreleased app change, it can therefore recover that
app release. Otherwise docs/standalone website pushes skip the build/release job.
Before the first managed release, the push's `before` commit is the baseline;
a manual bootstrap or newly created branch uses the empty tree.

Release inputs include `lib/`, `assets/`, `android/`, local `packages/`, build
hooks/configuration, `pubspec.yaml`, `pubspec.lock`, the release workflow/helper,
and its tests. Renames and deletions count. `docs/`, `README.md`, `website/`,
Flutter web hosting files, unrelated desktop/iOS files, and the macOS workflow do
not trigger a release by themselves. Extend `APP_FILES`/`APP_PREFIXES` in
`tool/android_release.py` when introducing a new app build input.

The Android versionCode is the maximum of:

- `GITHUB_RUN_NUMBER`;
- one above every existing `android-vMAJOR.MINOR.CODE` tag or release, including drafts;
- one above the `pubspec.yaml` build number;
- one above `ANDROID_VERSION_CODE_FLOOR`, if configured.

The versionName is `MAJOR.MINOR.CODE`, with major/minor taken from `pubspec.yaml`.
For example, code 23 produces tag `android-v1.0.23` and
`tashbihh-v1.0.23.apk`. No manual version bumps, source commits, or tag updates
are needed. Gaps are allowed. Android's maximum code of 2,100,000,000 is enforced.
Keep the workflow's tags and releases: they preserve the version high-water mark.

One concurrency group serializes planning through publication. GitHub may replace
pending runs; the last-release comparison recovers their changes. Rerunning an
already released commit skips; old commits cannot publish over a newer release.
Diverged/force-pushed release history fails safely and needs history repair.

## Build and publication checks

CI pins Flutter **3.47.9** (Dart **3.13.7**) and Java **17**. The existing Kotlin
DSL, AGP **9.1.0**, Gradle **9.3.1**, and Kotlin plugin **2.4.0** are retained.
Flutter installs the required Android SDK/NDK components on the hosted runner.
When upgrading Flutter, update the workflow pin with `pubspec.yaml` constraints
and verify Gradle compatibility together. Dependencies use the committed lockfile.
Keep the build's normal dependency/tooling regeneration enabled. On this SDK,
using `--no-pub` after tests can leave development plugins in the generated Android
registrant and break release Java compilation; see
[Flutter's upstream report](https://github.com/flutter/flutter/pull/194204).

Missing/invalid signing secrets stop before the Flutter build. Analysis, app
tests, and release automation tests must pass. `flutter build apk --release`
builds a single universal APK with the chosen version arguments. `apksigner`
verifies its signature against the pinned certificate; `aapt` verifies package
ID, version and non-debuggable mode; ZIP inspection verifies ARMv7/ARM64/x86_64
Flutter and app libraries. The prior release APK, if present, must have the same
certificate and a lower versionCode.

Signing validation and final APK verification both export the public leaf
certificate from the configured keystore and alias, and hash its DER bytes.
The build and verification steps explicitly receive the same keystore path and
alias. The verifier accepts upper/lowercase hex, colons and whitespace, then
requires exactly 64 hex digits. It requires one APK signer and a matching
certificate in every reported SDK range. Public key digests and source-stamp
certificates are separate identities and are not accepted as APK signer digests.

Both numbered and v3.1 SDK-range labels are supported. Android's
[apksigner implementation](https://android.googlesource.com/platform/tools/apksig/+/refs/heads/main/src/apksigner/java/com/android/apksigner/ApkSignerTool.java)
prints SDK ranges instead of `Signer #1` for v3.1 signatures. The former
numbered-only regex could report a signer mismatch with no parsed certificates.

Only then does GitHub generate PR release notes, supplemented with every commit
since the previous release, including direct pushes. The workflow creates a new
draft, uploads the APK/checksum, checks asset upload state and size, then
publishes that new draft. Older releases, tags and assets are never edited,
replaced, or deleted. A failed publication may leave an unpublished draft for
inspection; rerunning allocates a fresh version instead of overwriting it.
Private keys/passwords are never uploaded. The temporary keystore is removed
even if a build fails.

## Local release builds

Create ignored `android/key.properties` with your original signing material:

```properties
storeFile=/absolute/path/to/tashbihh-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=tasbih
keyPassword=YOUR_KEY_PASSWORD
```

Use Java properties escaping for backslashes/special characters. Alternatively,
set `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD`. If any signing environment variable is present, all four
must be provided; Gradle never mixes partial environment credentials with local
properties. Relative store paths
resolve from `android/`. Debug builds do not need any of these values.

```sh
python3 -m unittest discover -s tool/tests -v
flutter analyze
flutter test
flutter build apk --release --build-name 1.0.23 --build-number 23
```

Do not manually distribute a versionCode that CI might reuse; update the
repository floor first if you distribute builds outside this workflow.

## Diagnose an APK signer verification failure

Do not replace the signing key or change the certificate pin to match an
unintended APK. If the initial **Validate production signing secrets** step
passes, the selected keystore alias already matched the pin in that run. That
alone does not prove the final APK was signed with it.

In **Actions → Android APK Release → release**, inspect the final verification
step. It prints the configured keystore certificate SHA-256, the APK's public
`apksigner verify --verbose --print-certs` report, and the expected pin. Passwords,
keystore Base64 and private keys are never printed. The APK digest must match
both the keystore certificate digest and the pin after normalization. A
`CN=Android Debug` certificate is evidence of a debug signing identity; check
the actual certificate digest rather than relying only on its name.

If verification fails, the workflow retains only the APK as an artifact named
`unverified-android-apk-RUN_ID-ATTEMPT` for three days. This is a diagnostic
artifact, not a published release. Download it from that run's Artifacts section
and run this in a terminal on your computer (adjust SDK version and APK path):

```sh
"$HOME/Android/Sdk/build-tools/36.0.0/apksigner" verify --verbose --print-certs \
  /path/to/downloaded/app-release.apk
```

If the pin really is wrong, derive the correct value from the **existing
production keystore and exact release alias**, not from a debug APK, a public
key digest, the keystore file hash or a Google Play certificate for another key.
This command prompts for the keystore password and displays only public
certificate information:

```sh
keytool -list -v -keystore /absolute/path/to/existing-production.jks \
  -alias YOUR_EXISTING_RELEASE_ALIAS
```

Copy only its **SHA256** fingerprint into repository secret
`ANDROID_SIGNING_CERT_SHA256`. Colons, letter case and whitespace are normalized.
To avoid locale-dependent field names or copying, this Bash/zsh command exports
only the public certificate, computes the digest, and uploads it via stdin.
Replace the keystore path and alias first. Never enable shell tracing:

```sh
(
  set -eu
  umask 077
  cert_dir=$(mktemp -d)
  trap 'rm -rf -- "$cert_dir"' EXIT
  keytool -exportcert -keystore /absolute/path/to/existing-production.jks \
    -alias YOUR_EXISTING_RELEASE_ALIAS -file "$cert_dir/certificate.der"
  python3 -c 'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' \
    "$cert_dir/certificate.der" > "$cert_dir/fingerprint.txt"
  gh secret set ANDROID_SIGNING_CERT_SHA256 --repo tushar-454/tashbihh-app \
    < "$cert_dir/fingerprint.txt"
)
```

Do not regenerate or upload the keystore, or change its alias/passwords, merely
to correct this certificate fingerprint.

### Investigation of run 41625319049

The [failed run](https://github.com/tushar-454/tashbihh-app/actions/runs/41625319049)
at commit `64449858bddc540e0937a0993ddb6c179fba55cf` passed the keystore/pin
comparison and built version `1.0.2`/code `2`. It logged neither the APK's
certificate report nor parsed digests, and retained no APK artifact. Therefore
the actual CI APK's signing identity and the exact failure cause cannot be
determined from that run. A new CI run must confirm the three-way certificate
comparison; the local parser fixes do not establish CI success.

The existing local Flutter output APK is version `1.0.0`/code `1` with an Android
Debug certificate. The separate Gradle output APK is version `1.0.42`/code `42`
with a prior local validation certificate. Neither is the failed CI artifact.
No production keystore is available locally, and no new key was generated for
this investigation.

## Validation of the signing verification changes

- All 40 release automation tests pass, including normalized fingerprints,
  numbered/SDK-range signer formats, multiple-signer rejection, mismatched keys,
  malformed digests, keytool failures and secret-safe diagnostics.
- `actionlint` and `git diff --check` pass.
- The two existing local APKs pass signature, identity, version, release-mode
  and universal-ABI checks against their own known public certificates; the
  stale debug APK is rejected against the other certificate.
- The real keytool export helper was exercised against the existing local debug
  keystore. This does not validate the unavailable production keystore.
- Gradle's release configuration selects the supplied keystore, alias and
  credentials, checked with the existing debug key as a configuration fixture
  without building an APK. Missing or partial release credentials are rejected;
  the debug task graph succeeds without signing credentials.

These checks do not verify the CI-signed production APK. No key was generated,
secret changed, APK re-signed or GitHub release published in this investigation.

## Initial release setup validation (historical)

Validated with Flutter 3.47.9/Dart 3.13.7 and the installed Java 21 runtime:

- `actionlint` 1.7.12 and YAML trigger/permission checks passed.
- `flutter analyze` passed; all 211 existing Flutter tests passed.
- All 23 release automation regression tests passed.
- A real universal release APK built with a temporary validation key; signature,
  package ID, version `1.0.42`/code `42`, release mode and all three ABIs verified.
- Missing signing credentials failed with the intended actionable Gradle error.
- Debug task configuration was checked without release credentials.

The validation key was deleted and the pre-existing Flutter release APK restored.
No GitHub release was published during that initial validation. CI uses Java 17,
the documented AGP requirement.

References: [Flutter Android signing](https://docs.flutter.dev/deployment/android),
[AGP 9.1 compatibility](https://developer.android.com/build/releases/agp-9-1-0-release-notes),
[Actions run numbers](https://docs.github.com/en/actions/reference/workflows-and-actions/variables),
[Actions concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[GitHub release generation](https://docs.github.com/en/rest/releases/releases#generate-release-notes-content-for-a-release).
