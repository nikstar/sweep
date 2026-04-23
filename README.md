![Sweep](docs/Header.png)

# Sweep

Sweep is a native Apple-platform torrent client built with Swift, SwiftUI, AppKit/UIKit where useful, and a Rust bridge around [`rqbit`](https://github.com/ikatson/rqbit).

The project is intentionally small and native. The macOS app follows the compact classic torrent-client shape: a dense torrent list, toolbar actions, progress detail, and a separate inspector panel. The iOS app shares the same core model and rqbit bridge so we can validate the Rust engine on device while building toward feature parity.

## Targets

- `Sweep`: macOS app.
- `Sweep-iOS`: iOS app.
- `SweepCore`: shared torrent model, persistence, formatting, and store logic.
- `SweepRQBitBridge`: Swift-facing bridge generated from the Rust `sweep-rqbit` crate.
- `rust/sweep-rqbit`: UniFFI-backed Rust wrapper around rqbit.

## Requirements

- Xcode 26 or newer.
- XcodeGen.
- Rust toolchain with `cargo`.
- A local Apple Development signing identity for device builds.

## Build

Generate the Xcode project after editing `project.yml`:

```sh
xcodegen generate
```

Build the macOS app:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS' build
```

Build the iOS app without signing:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The Xcode targets run `Scripts/build_rust_bridge.sh`. On macOS it builds and embeds `libsweep_rqbit.dylib`; on iOS it builds a static Rust library for the selected device or simulator target.

When Xcode is launched from Finder, it may not inherit your shell `PATH`. The build phase calls `Scripts/build_rust_bridge.sh`, which checks common Cargo locations such as `~/.cargo/bin/cargo`, `/opt/homebrew/bin/cargo`, and `/usr/local/bin/cargo`.

## Rust Patches

Sweep currently uses a pinned local checkout of rqbit under `references/rqbit`. That checkout is ignored by Git because it is upstream source, but the changes we rely on are tracked in this repo:

- `rust/patches/rqbit-tracker-compat.patch`
- `rust/patches/rqbit-piece-snapshot.patch`
- `rust/patches/rqbit-inspector-stats.patch`
- `rust/patches/librqbit-dualstack-sockets/`

The build script creates `references/rqbit` at the pinned revision when it is missing, then applies the tracked patches if needed. If you already have a checkout there, the script leaves it in place and only verifies/applies missing patches.

## Swift-Only UI Work

For quick Swift-only iteration, SwiftPM still works:

```sh
swift run Sweep
```

If the dynamic library is not available, the app launches with a local demo engine so UI work can continue independently.

## License

Sweep is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
