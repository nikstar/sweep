# Releasing Sweep

All distribution is pinned to **Nikita Starshinov — `6RX8GEVB43` (Individual)**.
The scripts do not accept a team override, and reject exported apps signed by
another team. The organization account is not used.

Requirements: Xcode signed in to the personal paid developer account, accepted
Apple agreements, Rust targets and XcodeGen as described in the README, and `gh`
signed in with write access to `nikstar/sweep`. Xcode manages provisioning and
distribution certificates, including cloud-managed signing when available.
No passwords or private keys belong in this repository.

Both scripts require a clean committed source tree. Versions come from command
arguments and apply to the app and Live Activity extension together. Build
numbers must increase for each TestFlight upload. Run platforms sequentially:
the shared Rust build regenerates the same Swift bindings and XCFramework.

## macOS → GitHub

```sh
# Build, sign with Developer ID, notarize using the Xcode account, and export.
Scripts/release_macos.sh --version 1.0 --build 2

# After pushing the source commit, publish that exact build and source revision.
Scripts/release_macos.sh --version 1.0 --build 2 --resume --publish \
  --tag v1.0-beta.2 --prerelease --notes docs/releases/1.0-beta.2.md
```

The universal app contains Apple Silicon and Intel slices, enables Hardened
Runtime, and must pass signature, personal-team, notarization-ticket and
Gatekeeper checks before publication. Xcode's `developer-id` upload performs
notarization; `-exportNotarizedApp` retrieves the stapled app. No separate
notarytool password is needed with this workflow. If Apple is still processing,
retry with `--resume`; do not submit a second build blindly.

GitHub receives a ZIP, SHA-256 checksums, and a manifest with the exact source
commit, personal team, Xcode version and artifact hash. Existing releases are
never overwritten, and the script never force-pushes tags or branches.

## iOS → private TestFlight

Create the app `me.nikstar.sweep.ios` under the personal App Store Connect
provider if it does not exist. Its internal testing group must contain only the
owner; automatic distribution may be enabled for that private group.

```sh
# Export and validate a personal-team App Store IPA, including its extension.
Scripts/release_testflight.sh --version 1.0 --build 2

# Upload using Xcode's signed-in account.
Scripts/release_testflight.sh --version 1.0 --build 2 --resume --publish
```

Both export and upload set `testFlightInternalTestingOnly=true`. This makes the
build ineligible for external TestFlight or App Store distribution. It does not
choose testers: check the internal group membership before assigning the build.
The script never creates a public invitation link or invites other testers.

Successful upload is distinct from Apple's processing finishing and the build
becoming available in the private group. Inspect App Store Connect → Sweep →
TestFlight after upload. Resolve any processing/export-compliance questions and
assign the build to the owner-only group if automatic distribution is not set.

## Outputs, recovery, and optional CI authentication

Archives, exports, validation logs and release manifests are under the ignored
`BuildArtifacts/Releases/<platform>-<version>-<build>/` directory. Keep archives
and dSYMs for crash symbolication. Treat distribution logs as local account data.

`--archive-only` stops after building and validating the personal-team archive.
`--resume` requires the identical commit, Xcode, team and version. A partially
created failed archive must be moved aside before retrying. If an upload has an
ambiguous outcome, inspect the upload log and App Store Connect before retrying
the same build; Apple may have accepted it even if the connection was lost.

For CI, all of `SWEEP_ASC_KEY_PATH`, `SWEEP_ASC_KEY_ID` and
`SWEEP_ASC_ISSUER_ID` may be supplied using a key from the personal provider.
Otherwise the signed-in Xcode account is used. Keys remain outside the repo.

Script checks:

```sh
python3 -m unittest discover -s Scripts/release -p 'test_*.py'
swift test
```
