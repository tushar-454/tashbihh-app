"""Release safety regressions; no GitHub requests or production signing keys."""

import importlib.util
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile


MODULE = Path(__file__).resolve().parents[1] / "android_release.py"
spec = importlib.util.spec_from_file_location("android_release", MODULE)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePlanningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous_cwd = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(self.cleanup)
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "test@example.invalid")
        Path("pubspec.yaml").write_text("name: tashbihh\nversion: 1.0.0+1\n")
        self.base = self.commit("lib/main.dart", "initial app")

    def cleanup(self):
        os.chdir(self.previous_cwd)
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self, path, content):
        file = Path(path)
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        self.git("add", "-A")
        self.git("commit", "-qm", content)
        return self.git("rev-parse", "HEAD")

    def published(self, tag="android-v1.0.7"):
        self.git("tag", tag, self.base)
        return {"tag_name": tag, "draft": False, "prerelease": False, "published_at": "2026-11-01T00:00:00Z"}

    def plan(self, releases=(), before=None, number=2, floor=0):
        return release.make_plan(list(releases), self.git("tag", "--list").splitlines(),
                                 {"before": before or self.base}, self.git("rev-parse", "HEAD"), number, floor)

    def test_docs_and_standalone_website_skip_initial_release(self):
        self.commit("README.md", "docs")
        self.commit("website/index.html", "website")
        self.commit("web/index.html", "Flutter web host only")
        self.assertEqual(self.plan()["release"], "false")

    def test_initial_app_push_gets_universal_asset_name(self):
        self.commit("lib/main.dart", "app update")
        result = self.plan()
        self.assertEqual(result["tag"], "android-v1.0.2")
        self.assertEqual(result["apk_name"], "tashbihh-v1.0.2.apk")

    def test_changes_since_last_release_survive_cancelled_pending_run(self):
        published = self.published()
        app_commit = self.commit("assets/config.json", "new app asset")
        self.commit("website/index.html", "website update")
        result = self.plan([published], before=app_commit)
        self.assertEqual(result["version_code"], "8")
        self.assertEqual(result["previous_tag"], published["tag_name"])

    def test_released_sha_rerun_is_noop(self):
        self.assertEqual(self.plan([self.published()])["release"], "false")

    def test_old_run_cannot_release_over_newer_commit(self):
        newer = self.commit("lib/main.dart", "newer app")
        published = self.published()
        self.git("tag", "-f", published["tag_name"], newer)
        self.git("checkout", "--detach", self.base)
        self.assertEqual(self.plan([published])["release"], "false")

    def test_diverged_history_fails_closed(self):
        branch_point = self.base
        self.base = self.commit("lib/main.dart", "released branch")
        published = self.published()
        self.git("checkout", "--detach", branch_point)
        self.commit("lib/main.dart", "diverged branch")
        with self.assertRaisesRegex(ValueError, "diverged"):
            self.plan([published])

    def test_move_out_of_app_folder_is_relevant(self):
        published = self.published()
        Path("docs").mkdir()
        self.git("mv", "lib/main.dart", "docs/main.dart")
        self.git("commit", "-qm", "move out of app")
        self.assertEqual(self.plan([published])["release"], "true")

    def test_deleted_app_file_is_relevant(self):
        published = self.published()
        self.git("rm", "lib/main.dart")
        self.git("commit", "-qm", "remove app file")
        self.assertEqual(self.plan([published])["release"], "true")

    def test_draft_and_orphan_tags_reserve_version_numbers(self):
        published = self.published()
        draft = dict(published, tag_name="android-v1.0.25", draft=True)
        self.git("tag", "android-v2.0.30")
        self.commit("pubspec.lock", "dependencies")
        self.assertEqual(self.plan([published, draft])["version_code"], "31")

    def test_manual_bootstrap(self):
        result = release.make_plan([], [], {}, self.base, 1, 0)
        self.assertEqual(result["version_code"], "2")

    def test_docs_only_after_release_skips(self):
        published = self.published()
        self.commit("docs/setup.md", "docs only")
        self.assertEqual(self.plan([published])["release"], "false")


class ReleaseSafetyTests(unittest.TestCase):
    def test_all_version_floors_and_run_number(self):
        self.assertEqual(release.next_version(50, 10, 1, ["android-v1.0.20"]), 50)
        self.assertEqual(release.next_version(2, 100, 1, []), 101)
        self.assertEqual(release.next_version(2, 0, 200, []), 201)
        with self.assertRaises(ValueError):
            release.next_version(2, 2_100_000_000, 1, [])

    def test_build_workflow_dependencies_assets_and_android_are_relevant(self):
        for path in ("lib/main.dart", "assets/font.ttf", "android/app/build.gradle.kts",
                     "pubspec.yaml", "pubspec.lock", "build.yaml", "l10n.yaml",
                     "packages/local/pubspec.yaml", ".github/workflows/android-release.yml",
                     "tool/android_release.py", "tool/tests/test_android_release.py"):
            with self.subTest(path=path):
                self.assertTrue(release.relevant(path))
        for path in ("website/style.css", "docs/android-releases.md", "README.md", "ios/Podfile",
                     ".github/workflows/macos-build.yml", "tool/prepare_web_offline.py"):
            with self.subTest(path=path):
                self.assertFalse(release.relevant(path))

    def test_missing_secrets_are_actionable(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "Missing GitHub Actions repository secrets.*ANDROID_KEYSTORE_BASE64"):
                release.signing()

    def test_fingerprint_format(self):
        self.assertEqual(release.certificate_fingerprint("AA:" * 31 + "AA"), "aa" * 32)
        with self.assertRaisesRegex(ValueError, "64-digit"):
            release.certificate_fingerprint("invalid")

    def test_apk_rejects_wrong_identity_signer_version_or_missing_abi(self):
        fingerprint = "ab" * 32
        signature = f"Signer #1 certificate SHA-256 digest: {fingerprint}"
        metadata = "package: name='com.example.tashbihh' versionCode='12' versionName='1.0.12'"
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "app.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
                    for library in ("libflutter.so", "libapp.so"):
                        archive.writestr(f"lib/{abi}/{library}", b"test fixture")
            with patch.object(release, "sdk_tool", side_effect=lambda name: name):
                with patch.object(release, "run", side_effect=[signature, metadata]):
                    release.verify_apk(apk, "12", "1.0.12", fingerprint)
                with patch.object(release, "run", return_value=signature):
                    with self.assertRaisesRegex(ValueError, "signer"):
                        release.verify_apk(apk, "12", "1.0.12", "cd" * 32)
                for invalid in (metadata.replace("tashbihh", "another_app"),
                                metadata.replace("versionCode='12'", "versionCode='11'"),
                                metadata + "\napplication-debuggable"):
                    with patch.object(release, "run", side_effect=[signature, invalid]):
                        with self.assertRaises(ValueError):
                            release.verify_apk(apk, "12", "1.0.12", fingerprint)
                with zipfile.ZipFile(apk, "w") as archive:
                    archive.writestr("lib/arm64-v8a/libflutter.so", b"split apk")
                with patch.object(release, "run", side_effect=[signature, metadata]):
                    with self.assertRaisesRegex(ValueError, "not universal"):
                        release.verify_apk(apk, "12", "1.0.12", fingerprint)

    def test_previous_apk_blocks_key_rotation_and_version_downgrades(self):
        fingerprint = "ab" * 32
        signature = f"Signer #1 certificate SHA-256 digest: {fingerprint}"
        with tempfile.TemporaryDirectory() as directory:
            env = {"RUNNER_TEMP": directory, "PREVIOUS_TAG": "android-v1.0.11",
                   "VERSION_CODE": "12", "VERSION_NAME": "1.0.12",
                   "ANDROID_SIGNING_CERT_SHA256": fingerprint}
            def response(*args):
                if args[:3] == ("gh", "release", "view"):
                    return json.dumps({"assets": [{"name": "previous.apk"}]})
                if args[:3] == ("gh", "release", "download"):
                    (Path(args[-1]) / "previous.apk").write_bytes(b"previous fixture")
                    return ""
                if args[0] == "apksigner":
                    return signature
                return "package: name='com.example.tashbihh' versionCode='12'"
            with patch.dict(os.environ, env), patch.object(release, "verify_apk"), \
                    patch.object(release, "sdk_tool", side_effect=lambda name: name), \
                    patch.object(release, "run", side_effect=response):
                with self.assertRaisesRegex(ValueError, "ANDROID_VERSION_CODE_FLOOR"):
                    release.verify()
                with patch.dict(os.environ, {"ANDROID_SIGNING_CERT_SHA256": "cd" * 32}):
                    with self.assertRaisesRegex(ValueError, "different signing key"):
                        release.verify()


class PublicationSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous_cwd = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(self.cleanup)
        Path("dist").mkdir()
        self.apk = Path("dist/tashbihh-v1.0.12.apk")
        self.apk.write_bytes(b"verified APK fixture")
        self.checksum = self.apk.with_suffix(".apk.sha256")
        digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.checksum.write_text(f"{digest}  {self.apk.name}\n")
        env = {"RELEASE_TAG": "android-v1.0.12", "GITHUB_REPOSITORY": "test/app",
               "GITHUB_SHA": "a" * 40, "APK_NAME": self.apk.name,
               "VERSION_NAME": "1.0.12", "VERSION_CODE": "12", "PREVIOUS_TAG": "android-v1.0.11",
               "RUNNER_TEMP": self.temp.name, "GITHUB_STEP_SUMMARY": str(Path(self.temp.name) / "summary")}
        self.environment = patch.dict(os.environ, env)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.commands = []

    def cleanup(self):
        os.chdir(self.previous_cwd)
        self.temp.cleanup()

    def response(self, *args):
        self.commands.append(args)
        if "matching-refs" in " ".join(args):
            return "[[]]"
        if "generate-notes" in " ".join(args):
            return json.dumps({"body": "Generated PR notes"})
        if args[:2] == ("git", "log"):
            return "- abc123 Direct push commit"
        if args[:3] == ("gh", "release", "view"):
            return json.dumps({"isDraft": True, "assets": [
                {"name": path.name, "size": path.stat().st_size, "state": "uploaded"}
                for path in (self.apk, self.checksum)]})
        return ""

    def assert_not_published(self):
        self.assertFalse(any(args[:3] == ("gh", "release", "edit") for args in self.commands))

    def test_success_uploads_draft_before_publishing_with_pr_and_commit_notes(self):
        with patch.object(release, "github_releases", return_value=[]), patch.object(release, "run", side_effect=self.response):
            release.publish()
        create = next(args for args in self.commands if args[:3] == ("gh", "release", "create"))
        edit = next(args for args in self.commands if args[:3] == ("gh", "release", "edit"))
        self.assertIn("--draft", create)
        self.assertIn("--draft=false", edit)
        notes = Path("android-release-notes.md").read_text()
        self.assertIn("Generated PR notes", notes)
        self.assertIn("Direct push commit", notes)
        self.assertIn("releases/download/android-v1.0.12/", notes)
        for args in self.commands:
            self.assertNotIn("--clobber", args)
            self.assertNotIn("delete", args)

    def test_existing_release_is_never_modified(self):
        with patch.object(release, "github_releases", return_value=[{"tag_name": "android-v1.0.12"}]), patch.object(release, "run", side_effect=self.response):
            with self.assertRaisesRegex(ValueError, "will not be overwritten"):
                release.publish()
        self.assertEqual(self.commands, [])

    def test_existing_orphan_tag_is_never_moved(self):
        with patch.object(release, "github_releases", return_value=[]), patch.object(release, "run", return_value='[[{"ref":"refs/tags/android-v1.0.12"}]]'):
            with self.assertRaisesRegex(ValueError, "will not be moved"):
                release.publish()

    def test_tampered_apk_is_never_uploaded(self):
        self.apk.write_bytes(b"changed after verification")
        with patch.object(release, "run", side_effect=self.response):
            with self.assertRaisesRegex(ValueError, "changed after verification"):
                release.publish()
        self.assertEqual(self.commands, [])

    def test_incomplete_upload_remains_unpublished(self):
        def incomplete(*args):
            response = self.response(*args)
            if args[:3] == ("gh", "release", "view"):
                return json.dumps({"isDraft": True, "assets": []})
            return response
        with patch.object(release, "github_releases", return_value=[]), patch.object(release, "run", side_effect=incomplete):
            with self.assertRaisesRegex(ValueError, "leaving.*draft"):
                release.publish()
        self.assert_not_published()

    def test_api_failure_cannot_be_mistaken_for_no_history(self):
        with patch.object(release, "run", side_effect=subprocess.CalledProcessError(1, ["gh", "api"])):
            with self.assertRaises(subprocess.CalledProcessError):
                release.publish()
        self.assert_not_published()


if __name__ == "__main__":
    unittest.main()
