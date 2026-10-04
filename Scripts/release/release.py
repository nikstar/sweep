#!/usr/bin/env python3
"""Release Sweep using the personal Apple team. No passwords are read or stored."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TEAM = "6RX8GEVB43"  # Nikita Starshinov, Individual (not the organization team).
REPO = "nikstar/sweep"


def fail(message):
    raise RuntimeError(message)


def run(*args, log=None):
    command = [str(a) for a in args]
    if log:
        print(f"Running {command[0]} {command[1]} — log: {log}", flush=True)
        with Path(log).open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            # Keep full signing/upload logs local; they can contain account metadata.
            fail(f"{command[0]} failed ({result.returncode}). Inspect {log}")
        return ""
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        fail(f"{' '.join(command[:2])} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def plist(path):
    with Path(path).open("rb") as f:
        return plistlib.load(f)


def write_plist(path, value):
    with Path(path).open("wb") as f:
        plistlib.dump(value, f)


def export_options(platform, upload=False):
    options = dict(teamID=TEAM, signingStyle="automatic",
                   method="developer-id" if platform == "macos" else "app-store-connect",
                   destination="upload" if upload else "export",
                   manageAppVersionAndBuildNumber=False)
    if platform == "testflight":
        options.update(testFlightInternalTestingOnly=True, uploadSymbols=True, stripSwiftSymbols=True)
    return options


def validate_version(version, build):
    if not re.fullmatch(r"\d{1,4}(?:\.\d{1,2}){0,2}", version):
        fail("Version must be numeric, for example 1.0 or 1.0.1.")
    if not re.fullmatch(r"[1-9]\d{0,3}(?:\.\d{1,2}){0,2}", build):
        fail("Build must be an increasing CFBundleVersion, for example 2 or 2026.10.4.")


def validate_metadata(info, bundle_id, version, build):
    for key, expected in {"CFBundleIdentifier": bundle_id,
                          "CFBundleShortVersionString": version, "CFBundleVersion": build}.items():
        if info.get(key) != expected:
            fail(f"{bundle_id}: {key} is {info.get(key)!r}, expected {expected!r}")


def signature(app):
    result = subprocess.run(["codesign", "-dvv", str(app)], text=True, capture_output=True)
    if result.returncode:
        fail(f"Cannot inspect signature of {app}")
    details = result.stderr
    if f"TeamIdentifier={TEAM}\n" not in details:
        fail(f"Refusing artifact signed by a different team: {app}")
    return details


def verify_app(app, platform, version, build, distribution=False):
    app = Path(app)
    is_mac = platform == "macos"
    base = app / "Contents" if is_mac else app
    bundle_id = "me.nikstar.sweep" if is_mac else "me.nikstar.sweep.ios"
    validate_metadata(plist(base / "Info.plist"), bundle_id, version, build)
    run("codesign", "--verify", "--deep", "--strict", app)
    details = signature(app)
    if is_mac:
        if "runtime" not in details:
            fail("Mac release is missing Hardened Runtime.")
        archs = set(run("lipo", "-archs", base / "MacOS/Sweep").split())
        if archs != {"arm64", "x86_64"}:
            fail(f"Mac release must be universal, got {archs}")
        if distribution and "Authority=Developer ID Application: Nikita Starshinov" not in details:
            fail("Mac export is not signed with the personal Developer ID Application certificate.")
    else:
        extension = app / "PlugIns/SweepLiveActivityExtension.appex"
        validate_metadata(plist(extension / "Info.plist"), bundle_id + ".liveactivity", version, build)
        signature(extension)
        if plist(base / "Info.plist").get("UIDeviceFamily") != [1]:
            fail("iOS release must remain iPhone-only.")
        if any("Sweep" in p.name or "rqbit" in p.name.lower() for p in app.rglob("*.framework")):
            fail("Unexpected embedded Rust/internal framework; bridge must be statically linked.")
        if distribution:
            for signed in [app, extension]:
                profile = plistlib.loads(subprocess.check_output(
                    ["security", "cms", "-D", "-i", str(signed / "embedded.mobileprovision")]))
                if profile.get("TeamIdentifier") != [TEAM] or profile.get("ProvisionedDevices"):
                    fail(f"Not a personal App Store distribution profile: {signed}")
                entitlements = profile.get("Entitlements", {})
                if entitlements.get("get-task-allow") or not entitlements.get("beta-reports-active"):
                    fail(f"Profile is not suitable for TestFlight: {signed}")


def xcode_auth():
    # Optional CI authentication. The exported artifact still must match TEAM.
    names = ["SWEEP_ASC_KEY_PATH", "SWEEP_ASC_KEY_ID", "SWEEP_ASC_ISSUER_ID"]
    values = [os.environ.get(name) for name in names]
    if any(values) and not all(values):
        fail("Set all three SWEEP_ASC_KEY_PATH, SWEEP_ASC_KEY_ID, SWEEP_ASC_ISSUER_ID or none.")
    if not all(values):
        return ["-allowProvisioningUpdates"]
    return ["-allowProvisioningUpdates", "-authenticationKeyPath", values[0],
            "-authenticationKeyID", values[1], "-authenticationKeyIssuerID", values[2]]


def check_source():
    if run("git", "status", "--porcelain", "--untracked-files=normal"):
        fail("Commit source changes before releasing; release artifacts must identify an exact clean commit.")
    return run("git", "rev-parse", "HEAD")


def write_manifest(out, config, files):
    manifest = {**config, "artifacts": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    (out / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (out / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in manifest["artifacts"].items()))


def release(args):
    validate_version(args.version, args.build)
    commit = check_source()
    out = ROOT / "BuildArtifacts/Releases" / f"{args.platform}-{args.version}-{args.build}"
    out.mkdir(parents=True, exist_ok=True)
    config = dict(platform=args.platform, version=args.version, build=args.build,
                  teamID=TEAM, commit=commit, xcode=run("xcodebuild", "-version"))
    config_path = out / "source.json"
    if args.resume:
        if not config_path.exists() or json.loads(config_path.read_text()) != config:
            fail("Resume requires the same source commit, version, build, team, and Xcode.")
    elif config_path.exists():
        fail(f"Output already exists. Use --resume or choose a new build number: {out}")
    else:
        config_path.write_text(json.dumps(config, indent=2) + "\n")

    archive = out / "Sweep.xcarchive"
    auth = xcode_auth()
    if not (out / "archive.ok").exists():
        if archive.exists():
            fail(f"Incomplete archive exists. Move it aside before retrying: {archive}")
        scheme = "Sweep" if args.platform == "macos" else "Sweep-iOS"
        destination = "generic/platform=macOS" if args.platform == "macos" else "generic/platform=iOS"
        command = ["xcodebuild", "archive", "-project", ROOT / "Sweep.xcodeproj", "-scheme", scheme,
                   "-configuration", "Release", "-destination", destination,
                   "-archivePath", archive, "-derivedDataPath", ROOT / "DerivedData/Release",
                   "-clonedSourcePackagesDirPath", ROOT / ".build", "-onlyUsePackageVersionsFromResolvedFile",
                   *auth, f"DEVELOPMENT_TEAM={TEAM}", "CODE_SIGN_STYLE=Automatic",
                   "CODE_SIGN_IDENTITY=Apple Development", f"MARKETING_VERSION={args.version}",
                   f"CURRENT_PROJECT_VERSION={args.build}", "ONLY_ACTIVE_ARCH=NO"]
        if args.platform == "macos":
            command += ["ARCHS=arm64 x86_64", "ENABLE_HARDENED_RUNTIME=YES"]
        run(*command, log=out / "archive.log")
        verify_app(archive / "Products/Applications/Sweep.app", args.platform, args.version, args.build)
        (out / "archive.ok").touch()
    verify_app(archive / "Products/Applications/Sweep.app", args.platform, args.version, args.build)
    if check_source() != commit:
        fail("Source changed during the build.")
    if args.archive_only:
        print(f"Verified personal-team archive: {archive}")
        return

    if args.platform == "macos":
        macos(args, out, archive, auth, config)
    else:
        testflight(args, out, archive, auth, config)


def export(archive, out, platform, auth, upload=False, name="export"):
    options = out / f"{name}-options.plist"
    write_plist(options, export_options(platform, upload))
    run("xcodebuild", "-exportArchive", "-archivePath", archive,
        "-exportPath", out / name, "-exportOptionsPlist", options, *auth, log=out / f"{name}.log")


def macos(args, out, archive, auth, config):
    # Xcode uses its signed-in personal account (including cloud-managed Developer ID)
    # for signing and notarization, avoiding a second stored password for notarytool.
    if not (out / "notarization-submitted.ok").exists():
        export(archive, out, "macos", auth, upload=True, name="notarization")
        (out / "notarization-submitted.ok").touch()
    app = out / "export/Sweep.app"
    if not app.exists():
        run("xcodebuild", "-exportNotarizedApp", "-archivePath", archive,
            "-exportPath", out / "export", log=out / "export-notarized.log")
    verify_app(app, "macos", args.version, args.build, distribution=True)
    run("xcrun", "stapler", "validate", app, log=out / "stapler.log")
    run("spctl", "--assess", "--type", "execute", "--verbose=2", app, log=out / "gatekeeper.log")
    archive_zip = out / f"Sweep-{args.version}-{args.build}-macOS-universal.zip"
    if not archive_zip.exists():
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive_zip)
    write_manifest(out, config, [archive_zip])
    if not args.publish:
        print(f"Signed and notarized release ready: {archive_zip}")
        return
    if not args.notes or not args.tag:
        fail("GitHub publication requires --tag and --notes (a Markdown file).")
    run("git", "check-ref-format", "refs/tags/" + args.tag)
    if check_source() != config["commit"]:
        fail("Source changed before publication.")
    # Publish only a commit already on GitHub. Never move or force-push an existing tag.
    remote_commit = json.loads(run("gh", "api", f"repos/{REPO}/commits/{config['commit']}"))["sha"]
    if remote_commit != config["commit"]:
        fail("Push this source commit to GitHub before publishing.")
    existing = subprocess.run(["gh", "release", "view", args.tag, "--repo", REPO], capture_output=True)
    if existing.returncode == 0:
        fail(f"Release {args.tag} already exists; refusing to replace public artifacts.")
    assets = [archive_zip, out / "SHA256SUMS", out / "release.json"]
    command = ["gh", "release", "create", args.tag, *assets, "--repo", REPO,
               "--target", config["commit"], "--title", f"Sweep {args.version} (build {args.build})",
               "--notes-file", Path(args.notes).resolve()]
    if args.prerelease:
        command.append("--prerelease")
    print(run(*command))


def testflight(args, out, archive, auth, config):
    export_dir = out / "export"
    ipas = list(export_dir.glob("*.ipa"))
    if not ipas:
        export(archive, out, "testflight", auth)
        ipas = list(export_dir.glob("*.ipa"))
    if len(ipas) != 1:
        fail(f"Expected exactly one exported IPA in {export_dir}")
    ipa = ipas[0]
    # Extract via ditto so signed symlinks and executable permissions are preserved.
    verification = out / "verified-ipa"
    if not verification.exists():
        run("ditto", "-x", "-k", ipa, verification)
    verify_app(verification / "Payload/Sweep.app", "testflight", args.version, args.build, distribution=True)
    write_manifest(out, config, [ipa])
    if not args.publish:
        print(f"Internal-only TestFlight IPA ready: {ipa}")
        return
    if (out / "uploaded.ok").exists():
        print("This build was already uploaded; check processing and the private tester group in App Store Connect.")
        return
    export(archive, out, "testflight", auth, upload=True, name="upload")
    (out / "uploaded.ok").touch()
    print(f"Uploaded {args.version} ({args.build}) to personal-team, internal-only TestFlight.")
    print("Apple must finish processing. Assign only the owner's private internal group; never enable external/public testing.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["macos", "testflight"])
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString, e.g. 1.0")
    parser.add_argument("--build", required=True, help="Increasing CFBundleVersion, e.g. 2")
    parser.add_argument("--resume", action="store_true", help="Reuse this exact commit's verified archive")
    parser.add_argument("--archive-only", action="store_true", help="Stop after a verified signed archive")
    parser.add_argument("--publish", action="store_true", help="Upload to TestFlight or publish the GitHub release")
    parser.add_argument("--tag", help="GitHub release tag (macOS only)")
    parser.add_argument("--notes", help="GitHub release Markdown file (macOS only)")
    parser.add_argument("--prerelease", action="store_true", help="Mark the GitHub release as a prerelease")
    args = parser.parse_args()
    if args.archive_only and args.publish:
        parser.error("--archive-only and --publish are mutually exclusive")
    # The shared bridge regenerates source and XCFrameworks. Do not overlap releases.
    lock_path = ROOT / "BuildArtifacts/release.lock"
    lock_path.parent.mkdir(exist_ok=True)
    try:
        with lock_path.open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail("Another release build is running. Wait for it before starting the next platform.")
            release(args)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
