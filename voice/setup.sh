#!/bin/bash
# Installs Lotus's natural voice (Kokoro, open-source, runs offline) into ~/Lotus/voice.
# Downloads about 340 MB once. Needs uv (https://docs.astral.sh/uv/).
set -euo pipefail
DEST="$HOME/Lotus/voice"
BASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
mkdir -p "$DEST"
cp "$(dirname "$0")/speak.py" "$DEST/"

command -v uv >/dev/null || { echo "Install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
[ -x "$DEST/.venv/bin/python" ] || uv venv --python 3.12 "$DEST/.venv"
uv pip install --python "$DEST/.venv/bin/python" "kokoro-onnx>=0.4" numpy

for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [ ! -s "$DEST/$f" ]; then
    curl -L --fail --progress-bar -o "$DEST/$f.part" "$BASE/$f"
    mv -f "$DEST/$f.part" "$DEST/$f"
  fi
done

echo '{"text": "Hi! I am Lotus. This is my new voice.", "voice": "af_heart"}' \
  | "$DEST/.venv/bin/python" "$DEST/speak.py" | tail -1
echo "Natural voice installed. Restart Lotus to use it."
