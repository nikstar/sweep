#!/bin/sh
set -eu

PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

if command -v cargo >/dev/null 2>&1; then
  CARGO="$(command -v cargo)"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
  CARGO="$HOME/.cargo/bin/cargo"
elif [ -x "/opt/homebrew/bin/cargo" ]; then
  CARGO="/opt/homebrew/bin/cargo"
elif [ -x "/usr/local/bin/cargo" ]; then
  CARGO="/usr/local/bin/cargo"
else
  echo "error: cargo was not found." >&2
  echo "Install Rust from https://rustup.rs, or make sure cargo exists at ~/.cargo/bin/cargo." >&2
  exit 127
fi

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST_PATH="$ROOT_DIR/rust/sweep-rqbit/Cargo.toml"
CRATE_DIR="$ROOT_DIR/rust/sweep-rqbit"
GENERATED_DIR="$ROOT_DIR/Sources/SweepRQBitBridge/Generated"

if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
  RUST_PROFILE="release"
  CARGO_RUN_PROFILE="--release"
else
  RUST_PROFILE="debug"
  CARGO_RUN_PROFILE=""
fi

build_host_bridge() {
  if [ "${RUST_PROFILE}" = "release" ]; then
    "$CARGO" build --release --manifest-path "$MANIFEST_PATH"
  else
    "$CARGO" build --manifest-path "$MANIFEST_PATH"
  fi

  BRIDGE_PATH="$ROOT_DIR/rust/target/$RUST_PROFILE/libsweep_rqbit.dylib"

  if command -v install_name_tool >/dev/null 2>&1; then
    install_name_tool -id "@rpath/libsweep_rqbit.dylib" "$BRIDGE_PATH"
  fi

  rm -rf "$GENERATED_DIR"
  mkdir -p "$GENERATED_DIR"

  cd "$CRATE_DIR"
  if [ -n "$CARGO_RUN_PROFILE" ]; then
    "$CARGO" run --quiet "$CARGO_RUN_PROFILE" --manifest-path "$MANIFEST_PATH" --bin uniffi-bindgen-swift -- \
      "$BRIDGE_PATH" "$GENERATED_DIR" \
      --swift-sources \
      --headers \
      --modulemap \
      --module-name sweep_rqbitFFI \
      --modulemap-filename module.modulemap
  else
    "$CARGO" run --quiet --manifest-path "$MANIFEST_PATH" --bin uniffi-bindgen-swift -- \
      "$BRIDGE_PATH" "$GENERATED_DIR" \
      --swift-sources \
      --headers \
      --modulemap \
      --module-name sweep_rqbitFFI \
      --modulemap-filename module.modulemap
  fi

  perl -pi -e 's/[ \t]+$//' "$GENERATED_DIR/sweep_rqbit.swift" "$GENERATED_DIR/sweep_rqbitFFI.h"
}

build_ios_bridge() {
  case "${PLATFORM_NAME:-}" in
    iphonesimulator)
      RUST_TARGET="${SWEEP_RUST_TARGET:-aarch64-apple-ios-sim}"
      ;;
    iphoneos)
      RUST_TARGET="${SWEEP_RUST_TARGET:-aarch64-apple-ios}"
      ;;
    *)
      echo "error: unsupported iOS platform '${PLATFORM_NAME:-unknown}'" >&2
      exit 1
      ;;
  esac

  if [ "${RUST_PROFILE}" = "release" ]; then
    "$CARGO" build --release --target "$RUST_TARGET" --manifest-path "$MANIFEST_PATH"
  else
    "$CARGO" build --target "$RUST_TARGET" --manifest-path "$MANIFEST_PATH"
  fi
}

case "${PLATFORM_NAME:-macosx}" in
  iphoneos | iphonesimulator)
    build_host_bridge
    build_ios_bridge
    exit 0
    ;;
esac

build_host_bridge
exit 0
