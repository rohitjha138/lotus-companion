#!/bin/bash
# Installs the optional tools Lotus can use, the same set its author runs. Everything installs into your
# home folder and runs on your Mac. Run any part again safely; finished steps are skipped.
#
#   ./extras.sh            voice, video tools, GitHub CLI, connectors   (~0.6 GB)
#   ./extras.sh --images   also ComfyUI + RealVisXL for professional images (~13 GB more)
set -uo pipefail
cd "$(dirname "$0")"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "uv (Python tool installer)"
if ! command -v uv >/dev/null; then
  echo "Installing uv from astral.sh (official installer)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
uv --version || { echo "uv is needed; see https://docs.astral.sh/uv/"; exit 1; }

step "Natural voice (Kokoro, offline, ~340 MB)"
VOICE_SETUP=$([ -f voice/setup.sh ] && echo voice/setup.sh || echo setup.sh)  # repo or inside Lotus.app
bash "$VOICE_SETUP" || echo "Voice setup failed; Lotus will use the Mac's built-in voice."

step "Video tools: auto-editor (cuts silences), yt-dlp (downloads)"
for tool in auto-editor yt-dlp; do
  if command -v "$tool" >/dev/null; then echo "$tool: $(command -v "$tool")"; else uv tool install "$tool"; fi
done
if command -v ffmpeg >/dev/null; then echo "ffmpeg: $(command -v ffmpeg)"
elif command -v brew >/dev/null; then brew install ffmpeg
else echo "ffmpeg not found: install it with Homebrew (brew install ffmpeg) or from https://ffmpeg.org"; fi

step "GitHub CLI (gh)"
if ! command -v gh >/dev/null; then
  ARCH=$([ "$(uname -m)" = arm64 ] && echo arm64 || echo amd64)
  TAG=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
  TMP=$(mktemp -d)
  curl -sL --fail -o "$TMP/gh.zip" "https://github.com/cli/cli/releases/download/v$TAG/gh_${TAG}_macOS_${ARCH}.zip" \
    && (cd "$TMP" && unzip -q gh.zip) && cp "$TMP"/gh_*/bin/gh "$BIN/gh" && chmod +x "$BIN/gh"
  rm -rf "$TMP"
fi
gh --version | head -1 && echo "Sign in once with: gh auth login"

step "Claude connectors (sign in to each once: run claude, then /mcp)"
CLAUDE=$(command -v claude || find "$HOME/Library/Application Support/Claude/claude-code" -path '*Contents/MacOS/claude' 2>/dev/null | head -1)
if [ -n "$CLAUDE" ]; then
  while read -r name url; do
    if "$CLAUDE" mcp get "$name" </dev/null >/dev/null 2>&1; then echo "$name: already added"
    else "$CLAUDE" mcp add -s user -t http "$name" "$url" </dev/null >/dev/null && echo "$name: added"; fi
  done <<'LIST'
hugging-face https://huggingface.co/mcp
scite https://api.scite.ai/mcp
airtable https://mcp.airtable.com/mcp
adobe-workfront https://mcp.workfront.adobe.com/mcp/v1/workfront
opusclip https://api.opus.pro/api/mcp
jasper https://mcp.jasper.ai/
LIST
else
  echo "Claude Code not found; install the Claude desktop app or Claude Code, then run this again."
fi

if [ "${1:-}" = "--images" ]; then
  step "ComfyUI + RealVisXL V5 (professional images, ~13 GB)"
  DEST="$HOME/Lotus/ComfyUI"
  [ -d "$DEST/.git" ] || git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$DEST"
  [ -x "$DEST/.venv/bin/python" ] || uv venv --python 3.12 "$DEST/.venv"
  uv pip install --python "$DEST/.venv/bin/python" torch torchvision torchaudio -r "$DEST/requirements.txt"
  MODEL="$DEST/models/checkpoints/RealVisXL_V5.0_fp16.safetensors"
  if [ ! -s "$MODEL" ]; then
    curl -L --fail --progress-bar -o "$MODEL.part" \
      https://huggingface.co/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors && mv -f "$MODEL.part" "$MODEL"
  fi
  [ -s "$MODEL" ] && echo "Images ready: ask Lotus for a photo or a sketch." || echo "Model download failed; run again to resume."
fi

step "Done"
echo "Restart Lotus to pick everything up."
