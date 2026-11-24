import subprocess
import unittest
from unittest.mock import patch

import release


class ReleaseSafetyTests(unittest.TestCase):
    def test_every_export_is_pinned_to_personal_team(self):
        for platform in ["macos", "testflight"]:
            for upload in [False, True]:
                options = release.export_options(platform, upload)
                self.assertEqual(options["teamID"], "6RX8GEVB43")
                self.assertFalse(options["manageAppVersionAndBuildNumber"])
                self.assertEqual(options["destination"], "upload" if upload else "export")

    def test_testflight_cannot_be_distributed_externally(self):
        for upload in [False, True]:
            options = release.export_options("testflight", upload)
            self.assertEqual(options["method"], "app-store-connect")
            self.assertIs(options["testFlightInternalTestingOnly"], True)

    def test_macos_uses_developer_id(self):
        self.assertEqual(release.export_options("macos")["method"], "developer-id")

    def test_macos_release_names_use_semver(self):
        self.assertEqual(release.macos_release_tag("1.1.0", None, False), "v1.1.0")
        beta = "v1.2.0-beta.1"
        self.assertEqual(release.macos_release_tag("1.2.0", beta, True), beta)
        for version, tag, prerelease in [
            ("1.01.0", None, False), ("1.0", None, False), ("1.2.0", beta, False),
            ("1.2.0", "v1.2.0-beta.01", True), ("1.2.0", "v1.2.0+123", False),
            ("1.2.0", "v1.3.0", False),
        ]:
            with self.subTest(tag=tag, version=version), self.assertRaises(RuntimeError):
                release.macos_release_tag(version, tag, prerelease)

    def test_stable_feed_only_advances(self):
        previous = {"version": "1.0", "build": "5"}
        release.validate_stable_update(previous, "1.1.0", "6")
        for version, build in [("1.0.0", "6"), ("0.9.9", "6"), ("1.1.0", "5.0"), ("1.1.0", "4")]:
            with self.subTest(version=version, build=build), self.assertRaises(RuntimeError):
                release.validate_stable_update(previous, version, build)

    def test_existing_tag_must_resolve_to_release_commit(self):
        ref = "refs/tags/v1.0"
        for response in [f"commit\t{ref}", f"tagobject\t{ref}\ncommit\t{ref}^{{}}"]:
            with patch("release.run", side_effect=["", response]):
                release.ensure_release_tag("v1.0", "commit")
            with patch("release.run", side_effect=["", response]):
                with self.assertRaisesRegex(RuntimeError, "different commit"):
                    release.ensure_release_tag("v1.0", "other")

    def test_missing_tag_is_created_at_exact_commit(self):
        with patch("release.run", return_value="") as run:
            release.ensure_release_tag("v1.0", "commit")
            run.assert_called_with("gh", "api", "--method", "POST", f"repos/{release.REPO}/git/refs",
                                   "-f", "ref=refs/tags/v1.0", "-f", "sha=commit")

    def test_nested_version_mismatch_fails(self):
        info = {"CFBundleIdentifier": "me.nikstar.sweep.ios.liveactivity",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
        with self.assertRaisesRegex(RuntimeError, "CFBundleVersion"):
            release.validate_metadata(info, info["CFBundleIdentifier"], "1.0", "2")

    def test_org_and_unsigned_artifacts_fail(self):
        for team in ["Y54Z4K69Z9", "not set", "6RX8GEVB43-incorrect"]:
            result = subprocess.CompletedProcess([], 0, "", f"TeamIdentifier={team}\n")
            with patch("release.subprocess.run", return_value=result):
                with self.assertRaisesRegex(RuntimeError, "different team"):
                    release.signature("Sweep.app")

    def test_personal_signature_succeeds(self):
        result = subprocess.CompletedProcess([], 0, "", "TeamIdentifier=6RX8GEVB43\n")
        with patch("release.subprocess.run", return_value=result):
            release.signature("Sweep.app")

    def test_invalid_versions_cannot_reach_xcode_or_paths(self):
        for version, build in [("../other", "2"), ("1.0-beta", "2"), ("1.0", "0"), ("1.0", "2026100401")]:
            with self.assertRaises(RuntimeError):
                release.validate_version(version, build)
        release.validate_version("1.0.1", "2026.10.4")

    def test_partial_api_credentials_fail(self):
        with patch.dict("release.os.environ", {"SWEEP_ASC_KEY_ID": "example"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "all three"):
                release.xcode_auth()


if __name__ == "__main__":
    unittest.main()
