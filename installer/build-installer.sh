#!/bin/bash
# OpenControl for PreSonus FireStudio — assemble l'installeur complet sur VOTRE Mac.
#
# Le dépôt ne contient aucun binaire PreSonus. Ce script extrait les drivers FireWire
# de l'installeur officiel Universal Control 3.4.2 (téléchargé par vous chez PreSonus),
# sans les modifier, puis les assemble avec l'application FireStudio Mixer.
#
# Usage :
#   installer/build-installer.sh [--app "FireStudio Mixer.app"] [--force] <source>
#     <source> : PreSonus_UniversalControl_v3_4_2_*.dmg, ou « PreSonus FireWire Driver.pkg »
#     --app    : application à inclure (par défaut : app/build, construite si absente)
#     --force  : accepter une version de driver différente de 4.2.1
#
# Résultat : dist/OpenControl-FireStudio-<version>-complet.pkg

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
[ -n "$SOURCE" ] || { echo "Indiquez l'installeur officiel PreSonus (.dmg ou .pkg). Voir --help." >&2; exit 2; }
[ -e "$SOURCE" ] || { echo "Introuvable : $SOURCE" >&2; exit 2; }

WORK="$(mktemp -d -t opencontrol)"
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet || true; fi
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf -- "$WORK"; fi
}
trap cleanup EXIT

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }

# 1. Localiser « PreSonus FireWire Driver.pkg »
DRIVER_PKG=""
case "$SOURCE" in
  *.dmg)
    sum="$(shasum -a 256 "$SOURCE" | cut -d' ' -f1)"
    if [ "$sum" = "$KNOWN_DMG_SHA256" ]; then say "Image disque reconnue : Universal Control 3.4.2"
    else warn "Image disque non reconnue (SHA-256 $sum) — vérification du contenu…"; fi
    MOUNT="$WORK/mnt"; mkdir -p "$MOUNT"
    hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" "$SOURCE" -quiet
    DRIVER_PKG="$(find "$MOUNT" -maxdepth 2 -name 'PreSonus FireWire Driver.pkg' | head -1)"
    ;;
  *.pkg) DRIVER_PKG="$SOURCE" ;;
  *) echo "Format non pris en charge : $SOURCE" >&2; exit 2 ;;
esac
[ -n "$DRIVER_PKG" ] || { echo "« PreSonus FireWire Driver.pkg » absent de cette image." >&2; exit 1; }

# 2. Signature PreSonus
if pkgutil --check-signature "$DRIVER_PKG" | grep -q "PreSonus"; then
  say "Signature PreSonus vérifiée"
else
  warn "Le paquet n'est pas signé par PreSonus."
  [ "$FORCE" = 1 ] || { echo "Abandon (utilisez --force si vous savez ce que vous faites)." >&2; exit 1; }
fi

# 3. Extraire les composants Audio et MIDI, inchangés
pkgutil --expand "$DRIVER_PKG" "$WORK/expanded"
mkdir -p "$WORK/pkgs"
for comp in "FW Audio Driver" "FW MIDI Driver"; do
  dir="$WORK/expanded/$comp.pkg"
  [ -d "$dir" ] || { echo "Composant manquant : $comp" >&2; exit 1; }
  info="$(grep -o '<pkg-info [^>]*>' "$dir/PackageInfo" | head -1)"
  ver="$(printf '%s' "$info" | sed -n 's/.* version="\([^"]*\)".*/\1/p')"
  id="$(printf '%s' "$info" | sed -n 's/.* identifier="\([^"]*\)".*/\1/p')"
  say "$comp : $id $ver"
  if [ "$ver" != "$EXPECTED_DRIVER" ] && [ "$FORCE" != 1 ]; then
    echo "Version $ver inattendue (attendue : $EXPECTED_DRIVER). Utilisez --force pour continuer." >&2; exit 1
  fi
done
pkgutil --flatten "$WORK/expanded/FW Audio Driver.pkg" "$WORK/pkgs/presonus-fw-audio.pkg"
pkgutil --flatten "$WORK/expanded/FW MIDI Driver.pkg" "$WORK/pkgs/presonus-fw-midi.pkg"

# 4. Application
if [ -z "$APP" ]; then
  APP="$ROOT/app/build/FireStudio Mixer.app"
  if [ ! -d "$APP" ]; then say "Construction de l'application…"; make -C "$ROOT/app" >/dev/null; fi
fi
[ -d "$APP" ] || { echo "Application introuvable : $APP" >&2; exit 1; }
say "Application : $APP ($(lipo -archs "$APP/Contents/MacOS/FireStudioMixer"))"
pkgbuild --quiet --component "$APP" --install-location /Applications \
  --identifier io.github.opencontrol-firestudio.mixer --version "$VERSION" "$WORK/pkgs/opencontrol-app.pkg"

# 5. Installeur produit
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/OpenControl-FireStudio-$VERSION-complet.pkg"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__DRIVER__/$EXPECTED_DRIVER/g" "$ROOT/installer/Distribution.xml" > "$WORK/Distribution.xml"
productbuild --quiet --distribution "$WORK/Distribution.xml" --resources "$ROOT/installer/resources" \
  --package-path "$WORK/pkgs" "$OUT"
say "Installeur prêt : $OUT"
echo "    Ce fichier contient des drivers PreSonus : gardez-le pour votre usage personnel, ne le redistribuez pas."
