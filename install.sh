#!/bin/bash
# Installs Lotus on this Mac in one go: builds the app, gives it a stable local signature (so macOS
# remembers its permissions), puts it in /Applications and opens it.
#
#   ./install.sh            the app (about 1 minute)
#   ./install.sh --extras   also the natural voice, video tools, GitHub CLI and connectors (~0.6 GB)
#   ./install.sh --all      also offline image generation (ComfyUI + RealVisXL, ~13 GB more)
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Lotus is a Mac app (macOS 14 or later). It doesn't run on Windows or Linux yet."
  exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
  echo "Lotus needs macOS 14 (Sonoma) or later."
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Lotus is built with Apple's free developer tools. Installing them now: click Install in the window"
  echo "that appears, wait for it to finish, then run ./install.sh again."
  xcode-select --install || true
  exit 1
fi

./signing-setup.sh
./build.sh --install

case "${1:-}" in
  --extras) ./extras.sh ;;
  --all) ./extras.sh --images ;;
esac

cat <<'DONE'

Lotus is installed and open. Next:
  1. Click the lotus in the menu bar › Sign in to Claude… (your own Claude account; Google sign-in works).
  2. Allow Microphone, Speech Recognition, Screen Recording and Accessibility when macOS asks
     (menu bar lotus › Check permissions… shows what's missing).
  3. Say "Hey Buddy", or click Lotus in the Dock to chat.
DONE
