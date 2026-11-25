#!/bin/bash
# Builds Lotus.app. Run with --install to copy it to /Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Lotus"
"$BIN" --selftest

APP=build/Lotus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Lotus"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources" && cp uninstall.sh icon/AppIcon.icns voice/setup.sh voice/speak.py voice/transcribe.py tools/image.py extras.sh "$APP/Contents/Resources/"
# A fixed local identity keeps macOS permissions across rebuilds (see signing-setup.sh); ad-hoc otherwise.
IDENTITY="-"
for name in "Lotus Local Signing" "Ember Local Signing"; do  # Ember = this app's earlier name
  security find-certificate -c "$name" >/dev/null 2>&1 && { IDENTITY="$name"; break; }
done
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Lotus 2>/dev/null || true
  rm -rf /Applications/Lotus.app
  cp -R "$APP" /Applications/
  open /Applications/Lotus.app
  echo "Installed to /Applications/Lotus.app"
fi
