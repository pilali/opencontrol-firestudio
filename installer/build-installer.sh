#!/bin/bash
# OpenControl for PreSonus FireStudio — builds the full installer on YOUR Mac.
#
# This repository contains no PreSonus binaries. This script extracts the FireWire drivers
# from the official Universal Control 3.4.2 installer (downloaded by you from PreSonus),
# without modifying them, and packages them together with the FireStudio Mixer app.
#
# Usage:
#   installer/build-installer.sh [--app "FireStudio Mixer.app"] [--force] <source>
#     <source>: PreSonus_UniversalControl_v3_4_2_*.dmg, or "PreSonus FireWire Driver.pkg"
#     --app   : app to include (default: app/build, built if missing)
#     --force : accept a driver version other than 4.2.1
#
# Output: dist/OpenControl-FireStudio-<version>-full.pkg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
EXPECTED_DRIVER="4.2.1"
KNOWN_DMG_SHA256="86e4a88806c6e4c7ad0fc625cab61555251136a68a8dd76a37dadcc33d5ae621"  # UC 3.4.2 (63992)

APP=""
FORCE=0
SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) SOURCE="$1"; shift ;;
  esac
done
[ -n "$SOURCE" ] || { echo "Give the official PreSonus installer (.dmg or .pkg). See --help." >&2; exit 2; }
[ -e "$SOURCE" ] || { echo "Not found: $SOURCE" >&2; exit 2; }

WORK="$(mktemp -d -t opencontrol)"
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet || true; fi
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf -- "$WORK"; fi
}
trap cleanup EXIT

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }

# 1. Locate "PreSonus FireWire Driver.pkg"
DRIVER_PKG=""
case "$SOURCE" in
  *.dmg)
    sum="$(shasum -a 256 "$SOURCE" | cut -d' ' -f1)"
    if [ "$sum" = "$KNOWN_DMG_SHA256" ]; then say "Known disk image: Universal Control 3.4.2"
    else warn "Unknown disk image (SHA-256 $sum) — checking its contents…"; fi
    MOUNT="$WORK/mnt"; mkdir -p "$MOUNT"
    hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" "$SOURCE" -quiet
    DRIVER_PKG="$(find "$MOUNT" -maxdepth 2 -name 'PreSonus FireWire Driver.pkg' | head -1)"
    ;;
  *.pkg) DRIVER_PKG="$SOURCE" ;;
  *) echo "Unsupported format: $SOURCE" >&2; exit 2 ;;
esac
[ -n "$DRIVER_PKG" ] || { echo "\"PreSonus FireWire Driver.pkg\" not found in this image." >&2; exit 1; }

# 2. PreSonus signature
if pkgutil --check-signature "$DRIVER_PKG" | grep -q "PreSonus"; then
  say "PreSonus signature verified"
else
  warn "The package is not signed by PreSonus."
  [ "$FORCE" = 1 ] || { echo "Aborting (use --force if you know what you are doing)." >&2; exit 1; }
fi

# 3. Extract the Audio and MIDI components, unmodified
pkgutil --expand "$DRIVER_PKG" "$WORK/expanded"
mkdir -p "$WORK/pkgs"
for comp in "FW Audio Driver" "FW MIDI Driver"; do
  dir="$WORK/expanded/$comp.pkg"
  [ -d "$dir" ] || { echo "Missing component: $comp" >&2; exit 1; }
  info="$(grep -o '<pkg-info [^>]*>' "$dir/PackageInfo" | head -1)"
  ver="$(printf '%s' "$info" | sed -n 's/.* version="\([^"]*\)".*/\1/p')"
  id="$(printf '%s' "$info" | sed -n 's/.* identifier="\([^"]*\)".*/\1/p')"
  say "$comp: $id $ver"
  if [ "$ver" != "$EXPECTED_DRIVER" ] && [ "$FORCE" != 1 ]; then
    echo "Unexpected version $ver (expected $EXPECTED_DRIVER). Use --force to continue." >&2; exit 1
  fi
done
pkgutil --flatten "$WORK/expanded/FW Audio Driver.pkg" "$WORK/pkgs/presonus-fw-audio.pkg"
pkgutil --flatten "$WORK/expanded/FW MIDI Driver.pkg" "$WORK/pkgs/presonus-fw-midi.pkg"

# 4. App
if [ -z "$APP" ]; then
  APP="$ROOT/app/build/FireStudio Mixer.app"
  if [ ! -d "$APP" ]; then say "Building the app…"; make -C "$ROOT/app" >/dev/null; fi
fi
[ -d "$APP" ] || { echo "App not found: $APP" >&2; exit 1; }
say "App: $APP ($(lipo -archs "$APP/Contents/MacOS/FireStudioMixer"))"
pkgbuild --quiet --component "$APP" --install-location /Applications \
  --identifier io.github.opencontrol-firestudio.mixer --version "$VERSION" "$WORK/pkgs/opencontrol-app.pkg"

# 5. Product installer
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/OpenControl-FireStudio-$VERSION-full.pkg"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__DRIVER__/$EXPECTED_DRIVER/g" "$ROOT/installer/Distribution.xml" > "$WORK/Distribution.xml"
productbuild --quiet --distribution "$WORK/Distribution.xml" --resources "$ROOT/installer/resources" \
  --package-path "$WORK/pkgs" "$OUT"
say "Installer ready: $OUT"
echo "    This file contains PreSonus drivers: keep it for your own use, do not redistribute it."
