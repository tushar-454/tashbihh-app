#!/usr/bin/env python3
"""Android release helpers. Uses only Python's standard library, git, gh and SDK tools."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


TAG_PATTERN = re.compile(r"android-v\d+\.\d+\.(\d+)")
APP_PREFIXES = ("lib/", "assets/", "android/", "packages/", "hook/", "hooks/")
APP_FILES = {
    "pubspec.yaml", "pubspec.lock", "build.yaml", "build.yml", "l10n.yaml",
    "analysis_options.yaml", ".metadata", ".fvmrc", "flutter_launcher_icons.yaml",
    "flutter_native_splash.yaml", ".github/workflows/android-release.yml",
}
APK_PATH = Path("build/app/outputs/flutter-apk/app-release.apk")
APPLICATION_ID = "com.example.tashbihh"
MAX_VERSION_CODE = 2_100_000_000


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def github_releases():
    # Do not treat API/authentication failures as an empty release history.
    pages = json.loads(run(
        "gh", "api", "--paginate", "--slurp",
        f"repos/{os.environ['GITHUB_REPOSITORY']}/releases?per_page=100",
    ))
    return [release for page in pages for release in page]


def relevant(path):
    return (
        path in APP_FILES or path.startswith(APP_PREFIXES)
        or path == "tool/android_release.py"
        or path.startswith("tool/tests/test_android_release")
        or path.startswith("tool/tests/fixtures/apksigner-")
    )


def tag_code(tag):
    match = TAG_PATTERN.fullmatch(tag)
    return int(match[1]) if match else 0


def next_version(run_number, floor, pubspec_code, tags):
    code = max(run_number, floor + 1, pubspec_code + 1,
               max((tag_code(tag) for tag in tags), default=0) + 1)
    if not 1 <= code <= MAX_VERSION_CODE:
        raise ValueError("Android versionCode exceeds the supported range (1..2100000000).")
    return code


def ancestor(older, newer):
    result = subprocess.run(["git", "merge-base", "--is-ancestor", older, newer], check=False)
    if result.returncode not in (0, 1):
        raise ValueError("Cannot resolve release history. Keep published tags and full git history.")
    return result.returncode == 0


def changed_files(base, head):
    # --no-renames considers both paths of moves, including moves out of app folders.
    result = subprocess.check_output([
        "git", "diff", "--name-only", "--no-renames", "-z", base, head,
    ])
    return [path.decode("utf-8", errors="surrogateescape")
            for path in result.split(b"\0") if path]


def make_plan(releases, tags, event, head, run_number, floor):
    managed = [r for r in releases if tag_code(r["tag_name"])]
    published = [r for r in managed if not r["draft"] and not r["prerelease"]]
    previous = max(published, key=lambda r: tag_code(r["tag_name"]), default=None)
    if previous:
        base = run("git", "rev-parse", f"refs/tags/{previous['tag_name']}^{{commit}}")
        if ancestor(head, base):
            return {"release": "false", "reason": "This commit is already released or older than the latest release."}
        if not ancestor(base, head):
            raise ValueError("main diverged from the latest Android release. Merge its history before releasing.")
    else:
        base = event.get("before", "")
        if not base or set(base) == {"0"}:
            # First branch push/manual bootstrap: compare against the empty git tree.
            base = subprocess.check_output(["git", "hash-object", "-t", "tree", "--stdin"], input=b"").decode().strip()
    changes = [path for path in changed_files(base, head) if relevant(path)]
    if not changes:
        return {"release": "false", "reason": "No unreleased Flutter/Android app changes."}

    pubspec = Path("pubspec.yaml").read_text()
    version = re.search(r"^version:\s*['\"]?(\d+)\.(\d+)\.\d+(?:[^\s+]*)(?:\+(\d+))?", pubspec, re.MULTILINE)
    name = re.search(r"^name:\s*([a-z][a-z0-9_]*)\s*$", pubspec, re.MULTILINE)
    if not version or not name:
        raise ValueError("pubspec.yaml must have a package name and a numeric major.minor.patch version.")
    code = next_version(run_number, floor, int(version[3] or 0),
                        tags + [r["tag_name"] for r in releases])
    version_name = f"{version[1]}.{version[2]}.{code}"
    # For initial migration, use the previous public release for the changelog.
    prior_public = [r for r in releases if not r["draft"] and not r["prerelease"]]
    notes_previous = previous or max(prior_public, key=lambda r: r["published_at"], default=None)
    print("App changes: " + ", ".join(changes))
    return {
        "release": "true", "version_code": str(code), "version_name": version_name,
        "tag": f"android-v{version_name}", "apk_name": f"{name[1]}-v{version_name}.apk",
        "previous_tag": notes_previous["tag_name"] if notes_previous else "",
    }


def plan():
    floor = int(os.environ.get("ANDROID_VERSION_CODE_FLOOR") or "0")
    if floor < 0:
        raise ValueError("ANDROID_VERSION_CODE_FLOOR must be a nonnegative integer.")
    values = make_plan(
        github_releases(), run("git", "tag", "--list").splitlines(),
        json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()),
        os.environ["GITHUB_SHA"], int(os.environ["GITHUB_RUN_NUMBER"]), floor,
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")
    print(json.dumps(values, indent=2))
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(values.get("reason", f"Android release planned: {values.get('tag')}") + "\n")


def certificate_fingerprint(value):
    normalized = re.sub(r"\s+", "", value.replace(":", "")).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        raise ValueError("Expected a 64-digit SHA-256 certificate fingerprint (colons and whitespace optional); check ANDROID_SIGNING_CERT_SHA256.")
    return normalized


def keystore_fingerprint():
    # Export only the public leaf certificate for the exact alias Gradle uses.
    # A file avoids hashing JVM warnings that can appear on keytool's stdout.
    with tempfile.TemporaryDirectory(prefix="android-certificate-") as directory:
        certificate = Path(directory) / "certificate.der"
        result = subprocess.run([
            "keytool", "-exportcert", "-keystore", os.environ["ANDROID_KEYSTORE_PATH"],
            "-storepass:env", "ANDROID_KEYSTORE_PASSWORD", "-alias", os.environ["ANDROID_KEY_ALIAS"],
            "-file", str(certificate),
        ], capture_output=True, check=False)
        if result.returncode or not certificate.is_file() or not certificate.stat().st_size:
            raise ValueError("Cannot read signing certificate. Check ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_ALIAS.")
        return hashlib.sha256(certificate.read_bytes()).hexdigest()


def verify_keystore_certificate(expected):
    actual = keystore_fingerprint()
    print(f"Keystore alias certificate SHA-256: {actual}")
    if actual != expected:
        raise ValueError("Keystore certificate does not match ANDROID_SIGNING_CERT_SHA256. "
                         "Confirm the existing production keystore and alias, then follow "
                         "docs/android-releases.md to correct the certificate pin. Do not replace the key.")


def signing():
    required = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS",
                "ANDROID_KEY_PASSWORD", "ANDROID_SIGNING_CERT_SHA256"]
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise ValueError("Missing GitHub Actions repository secrets: " + ", ".join(missing)
                         + ". Configure Settings > Secrets and variables > Actions. "
                         "See docs/android-releases.md. No debug signing fallback is allowed.")
    expected = certificate_fingerprint(os.environ["ANDROID_SIGNING_CERT_SHA256"])
    keystore = Path(os.environ["ANDROID_KEYSTORE_PATH"])
    try:
        data = base64.b64decode("".join(os.environ["ANDROID_KEYSTORE_BASE64"].split()), validate=True)
    except ValueError as error:
        raise ValueError("ANDROID_KEYSTORE_BASE64 is invalid. Encode the original keystore as described in docs/android-releases.md.") from error
    with keystore.open("wb") as output:
        keystore.chmod(0o600)
        output.write(data)
    verify_keystore_certificate(expected)
    print("Production keystore and pinned certificate verified. Key password will also be checked during signing.")


def sdk_tool(name):
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("ANDROID_HOME must point to an installed Android SDK.")
    candidates = [path for path in Path(sdk).glob(f"build-tools/*/{name}")
                  if re.fullmatch(r"\d+\.\d+\.\d+", path.parent.name)]
    if not candidates:
        raise ValueError(f"Android SDK tool {name} is missing. Install stable SDK build-tools.")
    return str(max(candidates, key=lambda p: tuple(map(int, p.parent.name.split(".")))))


def verify_apk_certificate(apk, expected_fingerprint):
    expected = certificate_fingerprint(expected_fingerprint)
    tool = sdk_tool("apksigner")
    verified = run(tool, "verify", "--verbose", "--print-certs", str(apk)).replace("\r\n", "\n")
    # This report contains public certificates/digests only, never keystore data.
    print(f"apksigner report ({tool}) for {Path(apk).name}:\n{verified}")
    # Labels vary by SDK: numbered, v3.1 SDK ranges, or Build Tools 37's
    # "V2 Signer:". Every certificate must match; never deduplicate signers.
    counts = re.findall(r"^Number of signers:[ \t]*(\d+)[ \t]*$", verified, re.MULTILINE)
    if counts != ["1"]:
        raise ValueError("APK must have exactly one signer; apksigner reported "
                         + (", ".join(counts) if counts else "no signer count") + ".")
    certificates = re.findall(
        r"^((?:Signer|V\d+(?:\.\d+)? Signer)[^\r\n]*?) certificate SHA-256 digest:[ \t]*([^\r\n]*)$",
        verified, re.MULTILINE,
    )
    numbered = [label for label, _ in certificates if re.fullmatch(r"Signer #\d+", label)]
    ranged = [label for label, _ in certificates if re.fullmatch(
        r"Signer \(minSdkVersion=\d+(?: \(dev release=true\))?, maxSdkVersion=\d+\)", label)]
    single = len(certificates) == 1 and (numbered == ["Signer #1"]
                                       or certificates[0][0] == "V2 Signer:")
    if not certificates or not (single or len(ranged) == len(certificates)):
        raise ValueError("Cannot identify exactly one APK signer from apksigner certificate output; "
                         "multiple or unrecognized signer records. Refusing publication.")
    fingerprints = [certificate_fingerprint(value) for _, value in certificates]
    print(f"APK {Path(apk).name} certificate SHA-256: {', '.join(fingerprints)}")
    print(f"Pinned production certificate SHA-256: {expected}")
    if any(value != expected for value in fingerprints):
        debug = bool(re.search(r"^(?:Signer|V\d+(?:\.\d+)? Signer)[^\r\n]* certificate DN:.*CN=Android Debug(?:,|$)",
                               verified, re.MULTILINE))
        raise ValueError("APK signer does not match the pinned production certificate. "
                         + ("APK certificate identifies itself as Android Debug. " if debug else "")
                         + "Check the release signing configuration, alias and stale APK outputs. "
                         "Do not change the pin to match an unintended APK.")


def verify_apk(apk, version_code, version_name, expected_fingerprint):
    verify_apk_certificate(apk, expected_fingerprint)
    metadata = run(sdk_tool("aapt"), "dump", "badging", str(apk))
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata, re.MULTILINE)
    if not package or package.groups() != (APPLICATION_ID, str(version_code), version_name):
        raise ValueError("APK applicationId/versionCode/versionName does not match the planned release.")
    if "application-debuggable" in metadata:
        raise ValueError("Refusing to publish a debuggable APK.")
    with zipfile.ZipFile(apk) as archive:
        entries = set(archive.namelist())
    for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
        if f"lib/{abi}/libflutter.so" not in entries or f"lib/{abi}/libapp.so" not in entries:
            raise ValueError(f"APK is not universal: missing Flutter/app libraries for {abi}.")
    print("APK signature, package ID, version, release mode and all three ABIs verified.")


def verify():
    verify_keystore_certificate(certificate_fingerprint(os.environ["ANDROID_SIGNING_CERT_SHA256"]))
    verify_apk(APK_PATH, os.environ["VERSION_CODE"], os.environ["VERSION_NAME"],
               os.environ["ANDROID_SIGNING_CERT_SHA256"])
    previous = os.environ.get("PREVIOUS_TAG", "")
    if previous:
        previous_release = json.loads(run("gh", "release", "view", previous, "--json", "assets"))
        if any(asset["name"].endswith(".apk") for asset in previous_release["assets"]):
            # Check the actual distributed APK too, preventing accidental key rotation or
            # a downgrade when migrating from an older/manual release scheme.
            with tempfile.TemporaryDirectory(prefix="previous-android-", dir=os.environ["RUNNER_TEMP"]) as directory:
                run("gh", "release", "download", previous, "--pattern", "*.apk", "--dir", directory)
                for old_apk in Path(directory).glob("*.apk"):
                    try:
                        verify_apk_certificate(old_apk, os.environ["ANDROID_SIGNING_CERT_SHA256"])
                    except ValueError as error:
                        raise ValueError("The previous release APK has a different signing key or invalid signer records. "
                                         "Restore that original key to preserve installed app updates and data.") from error
                    metadata = run(sdk_tool("aapt"), "dump", "badging", str(old_apk))
                    old_code = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", metadata, re.MULTILINE)
                    if not old_code or old_code[1] != APPLICATION_ID:
                        raise ValueError("Previous APK has an unexpected applicationId; inspect the release history before migrating.")
                    if int(os.environ["VERSION_CODE"]) <= int(old_code[2]):
                        raise ValueError("Previous APK versionCode is too high. Set repository variable ANDROID_VERSION_CODE_FLOOR to its versionCode and rerun.")
    Path("dist").mkdir(exist_ok=True)
    target = Path("dist") / os.environ["APK_NAME"]
    shutil.copyfile(APK_PATH, target)
    checksum = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".apk.sha256").write_text(f"{checksum}  {target.name}\n")


def publish():
    tag = os.environ["RELEASE_TAG"]
    repo = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    apk = Path("dist") / os.environ["APK_NAME"]
    checksum = apk.with_suffix(".apk.sha256")
    if not apk.is_file() or not checksum.is_file():
        raise ValueError("Verified APK/checksum missing. Refusing to create a release.")
    if checksum.read_text() != f"{hashlib.sha256(apk.read_bytes()).hexdigest()}  {apk.name}\n":
        raise ValueError("APK changed after verification. Refusing to create a release.")
    # Fresh read fails closed on API problems and collisions. Never edit an old release.
    if any(r["tag_name"] == tag for r in github_releases()):
        raise ValueError(f"Release {tag} already exists. It will not be overwritten; rerun to allocate a fresh version.")
    remote_tags = json.loads(run("gh", "api", "--paginate", "--slurp",
                                f"repos/{repo}/git/matching-refs/tags/{tag}"))
    if any(ref["ref"] == f"refs/tags/{tag}" for page in remote_tags for ref in page):
        raise ValueError(f"Tag {tag} already exists. It will not be moved or overwritten.")

    notes_args = ["gh", "api", f"repos/{repo}/releases/generate-notes", "-f", f"tag_name={tag}",
                  "-f", f"target_commitish={sha}"]
    previous = os.environ.get("PREVIOUS_TAG", "")
    if previous:
        notes_args += ["-f", f"previous_tag_name={previous}"]
    generated = json.loads(run(*notes_args))["body"]
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    download = f"{server}/{repo}/releases/download/{tag}/{apk.name}"
    revision_range = [f"{previous}..{sha}"] if previous else [sha]
    # GitHub's generated PR notes may omit direct pushes, so include every commit too.
    commits = run("git", "log", "--reverse", "--format=- %h %s", *revision_range)
    notes = (f"[Download {apk.name}]({download})\n\n"
             f"Android version: **{os.environ['VERSION_NAME']}** "
             f"(versionCode **{os.environ['VERSION_CODE']}**). "
             "Universal APK: ARMv7, ARM64, x86_64. SHA-256 checksum attached.\n\n"
             f"{generated}\n\n### Commits\n\n{commits}\n")
    notes_file = Path(os.environ["RUNNER_TEMP"]) / "android-release-notes.md"
    notes_file.write_text(notes)
    # Create a new draft, upload assets, then publish only that newly created draft.
    # A failed upload leaves a draft for inspection; subsequent runs allocate a new tag.
    run("gh", "release", "create", tag, str(apk), str(checksum), "--repo", repo,
        "--target", sha, "--title", f"Tasbih Counter {os.environ['VERSION_NAME']}",
        "--notes-file", str(notes_file), "--draft")
    uploaded = json.loads(run("gh", "release", "view", tag, "--repo", repo, "--json", "assets,isDraft"))
    assets = {asset["name"]: asset for asset in uploaded["assets"]}
    if not uploaded["isDraft"] or any(
        path.name not in assets or assets[path.name]["state"] != "uploaded"
        or assets[path.name]["size"] != path.stat().st_size for path in (apk, checksum)
    ):
        raise ValueError("Release assets are incomplete; leaving the new release as a draft.")
    run("gh", "release", "edit", tag, "--repo", repo, "--draft=false", "--latest")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"[Release {tag}]({server}/{repo}/releases/tag/{tag})\n\n[Download APK]({download})\n")
    print(f"Published {tag}: {download}")


if __name__ == "__main__":
    try:
        {"plan": plan, "signing": signing, "verify": verify, "publish": publish}[sys.argv[1]]()
    except (ValueError, KeyError, IndexError, OSError, subprocess.CalledProcessError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
