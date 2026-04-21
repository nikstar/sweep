# Sweep

Sweep is a native macOS torrent client experiment built with SwiftUI and a Rust bridge around [`rqbit`](https://github.com/ikatson/rqbit).

The app is organized so the shared torrent model and store can be reused by a future iOS client:

- `SweepCore`: shared model, formatting, store, and engine protocol.
- `SweepRQBitBridge`: macOS rqbit dynamic bridge.
- `Sweep`: macOS app bundle target.

The macOS UI is intentionally compact and Transmission-like: a toolbar, torrent table, menu commands, app settings, and a bottom inspector. The Xcode app target builds and embeds the Rust bridge dylib into the app bundle.

## Build

Generate the Xcode project after editing `project.yml`:

```sh
xcodegen generate
```

Build the app bundle:

```sh
xcodebuild -project Sweep.xcodeproj -scheme Sweep -configuration Debug -destination 'platform=macOS' build
```

The Xcode target runs `cargo build` for the Rust bridge and copies `libsweep_rqbit.dylib` into `Sweep.app/Contents/Frameworks`.

When Xcode is launched from Finder, it may not inherit your shell `PATH`. The build phase calls `Scripts/build_rust_bridge.sh`, which checks common Cargo locations such as `~/.cargo/bin/cargo`, `/opt/homebrew/bin/cargo`, and `/usr/local/bin/cargo`.

For quick Swift-only iteration, SwiftPM still works:

```sh
swift run Sweep
```

If the dynamic library is not available, the app launches with a local demo engine so UI work can continue independently.
