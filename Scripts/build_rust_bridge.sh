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

MANIFEST_PATH="${SRCROOT:-$(pwd)}/rust/sweep-rqbit/Cargo.toml"

if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
  "$CARGO" build --release --manifest-path "$MANIFEST_PATH"
else
  "$CARGO" build --manifest-path "$MANIFEST_PATH"
fi
