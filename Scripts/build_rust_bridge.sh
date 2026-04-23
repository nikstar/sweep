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
FFI_MODULE_DIR="$ROOT_DIR/Sources/SweepRustFFI"
ARTIFACTS_DIR="$ROOT_DIR/BuildArtifacts"
XCFRAMEWORK_PATH="$ARTIFACTS_DIR/SweepRustFFI.xcframework"
RQBIT_DIR="$ROOT_DIR/references/rqbit"
RQBIT_URL="${SWEEP_RQBIT_URL:-https://github.com/ikatson/rqbit.git}"
RQBIT_REVISION="${SWEEP_RQBIT_REVISION:-f9b4aee8}"
RQBIT_TRACKER_COMPAT_PATCH="$ROOT_DIR/rust/patches/rqbit-tracker-compat.patch"
RQBIT_PIECE_SNAPSHOT_PATCH="$ROOT_DIR/rust/patches/rqbit-piece-snapshot.patch"
RQBIT_INSPECTOR_STATS_PATCH="$ROOT_DIR/rust/patches/rqbit-inspector-stats.patch"
IOS_DEPLOYMENT_TARGET="${SWEEP_IOS_DEPLOYMENT_TARGET:-26.0}"

if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
  RUST_PROFILE="release"
  CARGO_RUN_PROFILE="--release"
else
  RUST_PROFILE="debug"
  CARGO_RUN_PROFILE=""
fi

host_sdk_root() {
  xcrun --sdk macosx --show-sdk-path
}

run_cargo() {
  sdk_root="$1"
  deployment_var="$2"
  deployment_target="$3"
  shift 3

  env \
    SDKROOT="$sdk_root" \
    "$deployment_var=$deployment_target" \
    PATH="$PATH" \
    HOME="$HOME" \
    CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
    RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" \
    "$@"
}

run_host_cargo() {
  HOST_SDKROOT="${SWEEP_HOST_SDKROOT:-$(host_sdk_root)}"
  HOST_MACOS_DEPLOYMENT_TARGET="${SWEEP_HOST_MACOSX_DEPLOYMENT_TARGET:-15.0}"

  run_cargo "$HOST_SDKROOT" MACOSX_DEPLOYMENT_TARGET "$HOST_MACOS_DEPLOYMENT_TARGET" "$@"
}

run_ios_cargo() {
  sdk="$1"
  shift

  IOS_SDKROOT="${SWEEP_IOS_SDKROOT:-$(xcrun --sdk "$sdk" --show-sdk-path)}"

  run_cargo "$IOS_SDKROOT" IPHONEOS_DEPLOYMENT_TARGET "$IOS_DEPLOYMENT_TARGET" "$@"
}

host_rust_target() {
  case "$(uname -m)" in
    arm64)
      echo "aarch64-apple-darwin"
      ;;
    x86_64)
      echo "x86_64-apple-darwin"
      ;;
    *)
      echo "error: unsupported host architecture '$(uname -m)'" >&2
      exit 1
      ;;
  esac
}

ensure_rust_target_installed() {
  rust_target="$1"

  if command -v rustup >/dev/null 2>&1; then
    if rustup target list --installed | grep -qx "$rust_target"; then
      return
    fi

    rustup target add "$rust_target"
    return
  fi

  echo "error: Rust target '$rust_target' is not installed." >&2
  echo "Install it with: rustup target add $rust_target" >&2
  exit 1
}

build_macos_target() {
  rust_target="$1"

  ensure_rust_target_installed "$rust_target"

  if [ "${RUST_PROFILE}" = "release" ]; then
    run_host_cargo "$CARGO" build --release --target "$rust_target" --manifest-path "$MANIFEST_PATH"
  else
    run_host_cargo "$CARGO" build --target "$rust_target" --manifest-path "$MANIFEST_PATH"
  fi
}

build_ios_target() {
  rust_target="$1"
  sdk="$2"

  ensure_rust_target_installed "$rust_target"

  if [ "${RUST_PROFILE}" = "release" ]; then
    run_ios_cargo "$sdk" "$CARGO" build --release --target "$rust_target" --manifest-path "$MANIFEST_PATH"
  else
    run_ios_cargo "$sdk" "$CARGO" build --target "$rust_target" --manifest-path "$MANIFEST_PATH"
  fi
}

generate_swift_bindings() {
  bridge_target="$1"
  BRIDGE_PATH="$ROOT_DIR/rust/target/$bridge_target/$RUST_PROFILE/libsweep_rqbit.dylib"

  if command -v install_name_tool >/dev/null 2>&1; then
    install_name_tool -id "@rpath/libsweep_rqbit.dylib" "$BRIDGE_PATH"
  fi

  rm -rf "$GENERATED_DIR"
  mkdir -p "$GENERATED_DIR"

  cd "$CRATE_DIR"
  if [ -n "$CARGO_RUN_PROFILE" ]; then
    run_host_cargo "$CARGO" run --quiet "$CARGO_RUN_PROFILE" --manifest-path "$MANIFEST_PATH" --bin uniffi-bindgen-swift -- \
      "$BRIDGE_PATH" "$GENERATED_DIR" \
      --swift-sources \
      --headers \
      --modulemap \
      --module-name sweep_rqbitFFI \
      --modulemap-filename module.modulemap
  else
    run_host_cargo "$CARGO" run --quiet --manifest-path "$MANIFEST_PATH" --bin uniffi-bindgen-swift -- \
      "$BRIDGE_PATH" "$GENERATED_DIR" \
      --swift-sources \
      --headers \
      --modulemap \
      --module-name sweep_rqbitFFI \
      --modulemap-filename module.modulemap
  fi

  perl -pi -e 's/[ \t]+$//' "$GENERATED_DIR/sweep_rqbit.swift" "$GENERATED_DIR/sweep_rqbitFFI.h"

  mkdir -p "$FFI_MODULE_DIR"
  cp "$GENERATED_DIR/sweep_rqbitFFI.h" "$FFI_MODULE_DIR/"
  cp "$GENERATED_DIR/module.modulemap" "$FFI_MODULE_DIR/"
}

create_rust_xcframework() {
  MACOS_ARM64_TARGET="${SWEEP_MACOS_ARM64_TARGET:-aarch64-apple-darwin}"
  MACOS_X86_64_TARGET="${SWEEP_MACOS_X86_64_TARGET:-x86_64-apple-darwin}"
  IOS_DEVICE_TARGET="${SWEEP_IOS_DEVICE_TARGET:-aarch64-apple-ios}"
  IOS_SIMULATOR_ARM64_TARGET="${SWEEP_IOS_SIMULATOR_ARM64_TARGET:-aarch64-apple-ios-sim}"
  IOS_SIMULATOR_X86_64_TARGET="${SWEEP_IOS_SIMULATOR_X86_64_TARGET:-x86_64-apple-ios}"
  UNIVERSAL_DIR="$ROOT_DIR/rust/target/universal-apple-darwin/$RUST_PROFILE"
  UNIVERSAL_SIMULATOR_DIR="$ROOT_DIR/rust/target/universal-apple-ios-simulator/$RUST_PROFILE"
  TMP_DIR=""

  mkdir -p "$ARTIFACTS_DIR"
  TMP_DIR="$(mktemp -d "$ARTIFACTS_DIR/.sweep-rust-xcframework.XXXXXX")"
  TMP_HEADERS_DIR="$TMP_DIR/Headers"
  TMP_XCFRAMEWORK_PATH="$TMP_DIR/SweepRustFFI.xcframework"

  cleanup_temp_artifacts() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
      rm -rf "$TMP_DIR"
    fi
  }

  trap cleanup_temp_artifacts EXIT INT TERM

  mkdir -p "$TMP_HEADERS_DIR"
  cp "$GENERATED_DIR/sweep_rqbitFFI.h" "$TMP_HEADERS_DIR/"
  cp "$GENERATED_DIR/module.modulemap" "$TMP_HEADERS_DIR/"

  xcodebuild -create-xcframework \
    -library "$UNIVERSAL_DIR/libsweep_rqbit.a" \
    -headers "$TMP_HEADERS_DIR" \
    -library "$ROOT_DIR/rust/target/$IOS_DEVICE_TARGET/$RUST_PROFILE/libsweep_rqbit.a" \
    -headers "$TMP_HEADERS_DIR" \
    -library "$UNIVERSAL_SIMULATOR_DIR/libsweep_rqbit.a" \
    -headers "$TMP_HEADERS_DIR" \
    -output "$TMP_XCFRAMEWORK_PATH" >/dev/null

  rm -rf "$XCFRAMEWORK_PATH"
  mv "$TMP_XCFRAMEWORK_PATH" "$XCFRAMEWORK_PATH"

  trap - EXIT INT TERM
  cleanup_temp_artifacts
}

build_binary_artifacts() {
  apply_rqbit_patches

  HOST_RUST_TARGET="${SWEEP_HOST_RUST_TARGET:-$(host_rust_target)}"
  MACOS_ARM64_TARGET="${SWEEP_MACOS_ARM64_TARGET:-aarch64-apple-darwin}"
  MACOS_X86_64_TARGET="${SWEEP_MACOS_X86_64_TARGET:-x86_64-apple-darwin}"
  IOS_DEVICE_TARGET="${SWEEP_IOS_DEVICE_TARGET:-aarch64-apple-ios}"
  IOS_SIMULATOR_ARM64_TARGET="${SWEEP_IOS_SIMULATOR_ARM64_TARGET:-aarch64-apple-ios-sim}"
  IOS_SIMULATOR_X86_64_TARGET="${SWEEP_IOS_SIMULATOR_X86_64_TARGET:-x86_64-apple-ios}"
  UNIVERSAL_DIR="$ROOT_DIR/rust/target/universal-apple-darwin/$RUST_PROFILE"
  UNIVERSAL_SIMULATOR_DIR="$ROOT_DIR/rust/target/universal-apple-ios-simulator/$RUST_PROFILE"

  build_macos_target "$HOST_RUST_TARGET"

  if [ "$HOST_RUST_TARGET" != "$MACOS_ARM64_TARGET" ]; then
    build_macos_target "$MACOS_ARM64_TARGET"
  fi

  if [ "$HOST_RUST_TARGET" != "$MACOS_X86_64_TARGET" ]; then
    build_macos_target "$MACOS_X86_64_TARGET"
  fi

  mkdir -p "$UNIVERSAL_DIR"
  lipo -create \
    "$ROOT_DIR/rust/target/$MACOS_ARM64_TARGET/$RUST_PROFILE/libsweep_rqbit.a" \
    "$ROOT_DIR/rust/target/$MACOS_X86_64_TARGET/$RUST_PROFILE/libsweep_rqbit.a" \
    -output "$UNIVERSAL_DIR/libsweep_rqbit.a"

  build_ios_target "$IOS_DEVICE_TARGET" iphoneos
  build_ios_target "$IOS_SIMULATOR_ARM64_TARGET" iphonesimulator
  build_ios_target "$IOS_SIMULATOR_X86_64_TARGET" iphonesimulator

  mkdir -p "$UNIVERSAL_SIMULATOR_DIR"
  lipo -create \
    "$ROOT_DIR/rust/target/$IOS_SIMULATOR_ARM64_TARGET/$RUST_PROFILE/libsweep_rqbit.a" \
    "$ROOT_DIR/rust/target/$IOS_SIMULATOR_X86_64_TARGET/$RUST_PROFILE/libsweep_rqbit.a" \
    -output "$UNIVERSAL_SIMULATOR_DIR/libsweep_rqbit.a"

  generate_swift_bindings "$HOST_RUST_TARGET"
  create_rust_xcframework
}

apply_rqbit_patches() {
  ensure_rqbit_checkout

  if [ ! -d "$RQBIT_DIR/.git" ]; then
    echo "error: expected rqbit reference checkout at $RQBIT_DIR" >&2
    exit 1
  fi

  apply_rqbit_patch_if_missing \
    "$RQBIT_TRACKER_COMPAT_PATCH" \
    "tracker compatibility" \
    "crates/tracker_comms/src/tracker_comms_http.rs" \
    "supportcrypto=1"
  apply_rqbit_patch_if_missing \
    "$RQBIT_PIECE_SNAPSHOT_PATCH" \
    "piece snapshot" \
    "crates/librqbit/src/torrent_state/mod.rs" \
    "pub fn piece_snapshot"
  apply_rqbit_patch_if_missing \
    "$RQBIT_INSPECTOR_STATS_PATCH" \
    "inspector stats" \
    "crates/tracker_comms/src/tracker_comms.rs" \
    "pub struct TrackerCommsState"
}

ensure_rqbit_checkout() {
  if [ -d "$RQBIT_DIR/.git" ]; then
    return
  fi

  if [ -e "$RQBIT_DIR" ]; then
    echo "error: $RQBIT_DIR exists but is not a git checkout." >&2
    exit 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "error: git was not found and rqbit checkout is missing at $RQBIT_DIR." >&2
    exit 127
  fi

  mkdir -p "$(dirname "$RQBIT_DIR")"
  git clone "$RQBIT_URL" "$RQBIT_DIR"
  git -C "$RQBIT_DIR" checkout "$RQBIT_REVISION"
}

apply_rqbit_patch_if_missing() {
  patch_path="$1"
  patch_name="$2"
  marker_file="$3"
  marker="$4"

  if grep -Fq "$marker" "$RQBIT_DIR/$marker_file"; then
    return
  fi

  apply_rqbit_patch "$patch_path" "$patch_name"
}

apply_rqbit_patch() {
  patch_path="$1"
  patch_name="$2"

  if git -C "$RQBIT_DIR" apply --reverse --check "$patch_path" >/dev/null 2>&1; then
    return
  fi

  if git -C "$RQBIT_DIR" apply --check "$patch_path" >/dev/null 2>&1; then
    git -C "$RQBIT_DIR" apply "$patch_path"
    return
  fi

  echo "error: could not apply rqbit $patch_name patch." >&2
  echo "The rqbit reference checkout may have changed; inspect $patch_path." >&2
  exit 1
}

build_binary_artifacts
exit 0
