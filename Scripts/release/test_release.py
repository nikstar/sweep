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
