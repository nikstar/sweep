# Sweep Agent Notes

This repository is a native Apple-platform torrent client built around `rqbit`.
The immediate goal is a polished macOS app with an iOS app that shares the same engine and data model.

## Product Intent

- Prefer compact, native UI over custom chrome.
- macOS should feel closer to classic Transmission than to a generic SwiftUI demo app.
- iOS should aim for feature parity where it makes sense, but the first priority there is that `rqbit` works reliably on device.
- Favor careful, incremental improvements over large rewrites.

## Repo Shape

- `Sources/SweepMac`: macOS app UI and app-specific behavior.
- `Sources/SweepIOS`: iOS app UI and app-specific behavior.
- `Sources/SweepCore`: shared models, formatting, persistence, and the `TorrentStore`.
- `Sources/SweepRQBitBridge`: Swift wrapper around the Rust UniFFI-generated API.
- `Sources/SweepRQBitBridge/Generated`: generated Swift bindings and headers. Do not hand-edit.
- `Sources/SweepRustFFI`: tracked system-library surface for SwiftPM (`module.modulemap` and header). Generated from the Rust bridge script.
- `rust/sweep-rqbit`: Rust crate wrapping `rqbit`.
- `rust/patches`: tracked patches applied to upstream `rqbit` and related crates.
- `Tests/SweepCoreTests`: unit tests for the shared layer.

## Build System

- Xcode project is generated from `project.yml`. If you change target structure or build settings, run:

```sh
xcodegen generate
```

- Shared Swift code is packaged as a local Swift package via `Package.swift`.
- App targets are still defined in XcodeGen.
- Rust artifacts are built by `Scripts/build_rust_bridge.sh` through the `SweepRustArtifacts` aggregate target.

## Rust Bridge Architecture

The current shape is intentional:

1. Rust crate `rust/sweep-rqbit` exposes UniFFI bindings.
2. `Scripts/build_rust_bridge.sh`:
   - ensures the pinned `references/rqbit` checkout exists
   - applies tracked local patches if missing
   - builds Rust for:
     - macOS `arm64`
     - macOS `x86_64`
     - iOS device `arm64`
     - iOS simulator `arm64`
     - iOS simulator `x86_64`
   - creates `BuildArtifacts/SweepRustFFI.xcframework`
   - regenerates Swift bindings into `Sources/SweepRQBitBridge/Generated`
   - copies the generated C header + module map into `Sources/SweepRustFFI`

3. SwiftPM consumes `Sources/SweepRustFFI` as a `systemLibrary` target named `sweep_rqbitFFI`.
4. App targets link the static archives from `BuildArtifacts/SweepRustFFI.xcframework`.

Important:

- Do not hand-edit `Sources/SweepRQBitBridge/Generated/*`.
- Do not reintroduce embedded dynamic frameworks for the Rust bridge. Static linkage is the working App Store-safe shape.
- TLS support is currently provided via `rustls`, not Apple-native TLS. That is deliberate to avoid private CommonCrypto symbol problems in App Store validation.

## rqbit / Rust Patches

We rely on a pinned local upstream checkout in `references/rqbit`, but that checkout itself is not tracked.
What *is* tracked is the patch set under `rust/patches/`.

If torrent behavior changes unexpectedly, check whether:

- upstream revision changed
- a patch no longer applies cleanly
- a patch marker stopped matching

Do not commit `references/rqbit` itself unless there is a deliberate change in repository policy.

## UI / Architecture Guidance

- Prefer existing local patterns over introducing new architecture.
- Shared app state lives in `TorrentStore` inside `SweepCore`.
- Use the `@Observable` macro for observable model types; do not add new `ObservableObject` code unless there is a very specific reason.
- For display preferences such as column layout/order/visibility, prefer system/native storage such as `UserDefaults` when appropriate. SQLite is mainly for torrent records, settings with structure, and persisted metadata.
- On macOS, preserve the dense classic-client feel. Avoid oversized spacing, nested cards, and iOS-style composition.
- On iOS, keep the app iPhone-only unless there is an explicit decision to expand device support.

## Current Platform Facts

- Minimum deployment targets:
  - macOS 15
  - iOS 26
- Bundle IDs:
  - macOS: `me.nikstar.sweep`
  - iOS: `me.nikstar.sweep.ios`
- Automatic signing is enabled for both app targets.
- iOS supports:
  - opening `magnet:` links
  - opening `.torrent` files via document registration
  - alternate icon `ClassicAppIcon`

## Known Quirks

- Xcode 26 `.icon` assets still produce some iPad-flavored icon metadata in the built iOS bundle even though the app is iPhone-only. This has shown up as non-blocking App Store “recommended icon” notices.
- The Rust build script runs every build because dependency analysis is disabled on that build phase.
- Xcode may emit an App Intents metadata warning if there is no AppIntents dependency. It is not currently a blocker.
- A stray `.xcodebuildmcp/` directory may appear locally from tooling. Do not commit it.

## Verification Checklist

For ordinary Swift-only changes:

```sh
swift test
```

For app changes:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Sweep.xcodeproj -scheme Sweep-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

For packaging-sensitive iOS changes, also inspect the built app plist:

```sh
plutil -p /tmp/.../Sweep.app/Info.plist
```

If you touched Rust bridge packaging, also verify:

- no embedded internal frameworks are present in the iOS app bundle
- no unexpected private symbol references appear
- macOS + iOS builds still succeed from a clean `BuildArtifacts/` state

## Editing Rules of Thumb

- Keep changes scoped.
- Avoid rewriting the main UI stack without a strong reason. A previous AppKit-backed rewrite of the macOS torrent list was reverted because it introduced more issues than it solved.
- If you change `project.yml`, regenerate `Sweep.xcodeproj`.
- If you touch the Rust bridge script or Rust FFI shape, verify both macOS and iOS builds.
- If you change persistence or shared formatting/state logic, run `swift test`.

## Handy Commands

Generate the project:

```sh
xcodegen generate
```

Run shared tests:

```sh
swift test
```

Build macOS:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS' build
```

Build iOS without signing:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Change Management

- Commit significant changes in focused commits.
- Keep generated project files in sync when `project.yml` changes.
- Do not silently revert user work or unrelated local changes.
