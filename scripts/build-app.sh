#!/bin/zsh
# Build "dist/SoundOne Control.app": the release app, its Bluetooth helper, Info.plist,
# and the icon. `--install` also puts it in /Applications. `--dmg` also packs it into
# "dist/SoundOne Control <version>.dmg" with an Applications link to drag it onto.
#
# macOS keys Bluetooth access to the app's signature. The script signs with
# SOUNDONE_SIGNING_IDENTITY, else a valid "Apple Development" or "Developer ID"
# certificate, else "SoundOne Control Local Signing" (scripts/signing-cert.sh). With any
# of them, access carries over between builds.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="SoundOne Control"
APP="$ROOT/dist/$APP_NAME.app"
INSTALL="/Applications/$APP_NAME.app"
BUNDLE_ID=com.amanamisrael.SoundOneControl
LOCAL_IDENTITY="SoundOne Control Local Signing"

install=false dmg=false
for arg; do
  case "$arg" in
    --install) install=true ;;
    --dmg) dmg=true ;;
    *) echo "Usage: scripts/build-app.sh [--install] [--dmg]" >&2; exit 2 ;;
  esac
done

swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/SoundOneControl" "$APP/Contents/MacOS/SoundOneControl"
cp "$BIN/SoundOneBluetoothAgent" "$APP/Contents/Helpers/SoundOneBluetoothAgent"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# The Liquid Glass icon (an Icon Composer document) compiles to Assets.car, plus
# AppIcon.icns for macOS 15. Info.plist names both.
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "${TMPDIR:-/tmp}/soundonecontrol-icon.plist" >/dev/null

IDENTITY="${SOUNDONE_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | grep -Eo '"(Apple Development|Developer ID Application): [^"]+"' | head -n 1 | tr -d '"' || true)}"
# Self-signed, so not "valid" to find-identity -v, but codesign uses it.
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning | grep -q "\"$LOCAL_IDENTITY\""; then
  IDENTITY="$LOCAL_IDENTITY"
fi
# Sign the helper before the app, so the app's seal covers the signed helper.
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID.BluetoothAgent" \
    "$APP/Contents/Helpers/SoundOneBluetoothAgent"
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  # Ad hoc pins access to the build's hash. Requiring only the identifier keeps
  # access across rebuilds, but any app with this identifier would match it.
  codesign --force --sign - --identifier "$BUNDLE_ID.BluetoothAgent" \
    "$APP/Contents/Helpers/SoundOneBluetoothAgent"
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
  echo "Ad hoc: run scripts/signing-cert.sh once so Bluetooth access is tied to a certificate." >&2
fi
echo "$APP (signed: ${IDENTITY:-ad hoc})"

if $install; then
  if pgrep -qf "$INSTALL/Contents/MacOS/SoundOneControl"; then
    echo "Quit $APP_NAME first: it is running from $INSTALL." >&2
    exit 1
  fi
  rm -rf "$INSTALL"
  ditto "$APP" "$INSTALL"
  echo "$INSTALL"
fi

if $dmg; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
  DMG="$ROOT/dist/$APP_NAME $VERSION.dmg"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  ditto "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  # hdiutil create is deprecated as of macOS 27; diskutil image is its replacement.
  diskutil image create from --volumeName "$APP_NAME" "$STAGE" "$DMG" >/dev/null
  if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$DMG"
  fi
  echo "$DMG"
fi
