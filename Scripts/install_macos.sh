#!/bin/sh
# Build the working tree and replace the local app only after a successful build.
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION=Release
LAUNCH=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration)
      [ "$#" -ge 2 ] || { echo 'Missing configuration (Debug or Release).' >&2; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --no-launch) LAUNCH=0; shift ;;
    --help|-h)
      echo 'Usage: Scripts/install_macos.sh [--configuration Debug|Release] [--no-launch]'
      echo 'Builds with your personal development team, installs /Applications/Sweep.app, and launches it.'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo 'Configuration must be Debug or Release.' >&2; exit 2 ;;
esac

DESTINATION=/Applications/Sweep.app
DERIVED_DATA="$ROOT_DIR/DerivedData/LocalInstall"
LOG_DIR="$ROOT_DIR/BuildArtifacts/LocalInstall"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build.log"

echo "Building Sweep ($CONFIGURATION). Log: $LOG"
if ! xcodebuild -project "$ROOT_DIR/Sweep.xcodeproj" -scheme Sweep \
  -configuration "$CONFIGURATION" -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$ROOT_DIR/.build" \
  -onlyUsePackageVersionsFromResolvedFile \
  DEVELOPMENT_TEAM=6RX8GEVB43 CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' build >"$LOG" 2>&1; then
  tail -n 80 "$LOG" >&2
  exit 1
fi

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Sweep.app"
/usr/bin/codesign --verify --deep --strict "$BUILT_APP"
SIGNATURE="$(/usr/bin/codesign -dv --verbose=4 "$BUILT_APP" 2>&1)"
printf '%s\n' "$SIGNATURE" | /usr/bin/grep -qx 'TeamIdentifier=6RX8GEVB43' || {
  echo 'Refusing to install: the app is not signed by the personal developer team.' >&2
  exit 1
}

# Stage on the same volume before stopping the app. Keep the previous bundle
# until replacement succeeds; never touch Application Support or downloaded data.
STAGING="$(mktemp -d /Applications/.Sweep-install.XXXXXX)"
cleanup() {
  if [ ! -e "$DESTINATION" ] && [ -d "$STAGING/Previous.app" ]; then
    mv "$STAGING/Previous.app" "$DESTINATION" || return
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
/usr/bin/ditto "$BUILT_APP" "$STAGING/Sweep.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/Sweep.app"

/usr/bin/osascript -e 'if application id "me.nikstar.sweep" is running then tell application id "me.nikstar.sweep" to quit'
ATTEMPT=0
while /usr/bin/pgrep -f '/Sweep[.]app/Contents/MacOS/Sweep( |$)' >/dev/null; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 30 ]; then
    echo 'Sweep did not quit. Close it, then run the installer again.' >&2
    exit 1
  fi
  sleep 1
done

if [ -e "$DESTINATION" ]; then
  [ ! -L "$DESTINATION" ] && [ -d "$DESTINATION" ] || {
    echo "Refusing to replace a non-bundle or symlink at $DESTINATION" >&2; exit 1;
  }
  mv "$DESTINATION" "$STAGING/Previous.app"
fi
mv "$STAGING/Sweep.app" "$DESTINATION"
echo "Installed $DESTINATION"
if [ "$LAUNCH" -eq 1 ]; then /usr/bin/open "$DESTINATION"; fi
