#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="SoundOne Control"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

swift build --package-path "$ROOT" -c release

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
cp "$ROOT/.build/release/SoundOneControl" "$CONTENTS/MacOS/SoundOneControl"
cp "$ROOT/.build/release/SoundOneBluetoothAgent" "$CONTENTS/Helpers/SoundOneBluetoothAgent"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"
fi

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
