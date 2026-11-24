#!/bin/bash
# Removes Lotus completely: the app, its memory, voice, caches, logs, settings, conversation history,
# signing certificate, and every macOS permission you gave it.
# Your Claude sign-in is kept, because Claude Code and the Claude app use it too.
set -u
pkill -x Lotus 2>/dev/null
pkill -f "Lotus/voice/speak.py" 2>/dev/null
sleep 1

rm -rf /Applications/Lotus.app \
       "$HOME/Lotus" \
       "$HOME/Library/Caches/Lotus" \
       "$HOME/Library/Caches/LotusVoice" \
       "$HOME/Library/Logs/Lotus-phone.log" "$HOME/Library/Logs/Lotus.log" \
       "$HOME/.claude/projects/${HOME//\//-}-Lotus"
defaults delete dev.ember.companion 2>/dev/null
tccutil reset All dev.ember.companion >/dev/null 2>&1  # microphone, speech, screen, accessibility, automation
security delete-certificate -c "Lotus Local Signing" >/dev/null 2>&1
security delete-certificate -c "Ember Local Signing" >/dev/null 2>&1  # from before the rename

echo "Lotus has been removed from this Mac."
