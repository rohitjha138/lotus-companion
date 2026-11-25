"""Lotus's extra-language ears: offline speech-to-text with faster-whisper.

Apple's on-device recognition only covers English and Hindi. This adds Nepali (and English and
Hindi) with a Whisper model that runs entirely on this Mac. Maithili has no model of its own, but
it shares the Devanagari script and much vocabulary with Hindi and Nepali, so Whisper transcribes it
as Devanagari text that Lotus (via Claude) understands.

Lotus keeps this running and writes one JSON request per line:
  {"wav": "/path/to/clip.wav", "lang": "auto"}   (lang "auto" detects; or "ne"/"hi"/"en")
It answers each with one line: the transcript (may be empty if nothing was heard).
"""
import json
import os
import sys

from faster_whisper import WhisperModel

# "small" is a good speed/accuracy balance on Apple Silicon (~460 MB). Override with LOTUS_WHISPER_MODEL.
model = WhisperModel(os.environ.get("LOTUS_WHISPER_MODEL", "small"), device="cpu", compute_type="int8")
print("ready", flush=True)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
        lang = req.get("lang") or None
        if lang == "auto":
            lang = None
        segments, _ = model.transcribe(req["wav"], language=lang, beam_size=1, vad_filter=True)
        print(" ".join(s.text.strip() for s in segments).strip().replace("\n", " "), flush=True)
    except Exception:
        print("", flush=True)  # blank = heard nothing; keep the loop alive for the next request
