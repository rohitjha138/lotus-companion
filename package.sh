#!/bin/bash
# Builds Lotus and wraps it in build/Lotus.dmg, a normal drag-to-Applications installer to share
# with other Macs. Each person signs in with their own Claude account; nothing of yours is included.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Lotus.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Lotus: a voice companion for your Mac, powered by Claude.

1. Drag Lotus into Applications.
2. Open it. If macOS says it can't verify the developer: System Settings > Privacy & Security >
   scroll down > Open Anyway. (Lotus is signed on its maker's Mac, not by Apple.)
3. Menu bar (sparkle icon) > Sign in to Claude... and sign in with your own Claude account
   (Google sign-in works). You need the Claude desktop app or Claude Code installed.
4. Allow Microphone, Speech Recognition, Screen Recording and Accessibility when asked.
5. Optional: sparkle > Install natural voice... for a human-sounding voice (runs offline).
6. Say "Hey Buddy" and ask anything.
TXT
rm -f build/Lotus.dmg
hdiutil create -volname Lotus -srcfolder "$STAGE" -ov -format UDZO build/Lotus.dmg >/dev/null
echo "Created build/Lotus.dmg ($(du -h build/Lotus.dmg | cut -f1))"
