"""Lotus's natural voice: Kokoro text-to-speech, running entirely on this Mac.

Lotus keeps this running and writes one JSON request per line:
  {"text": "Hello!", "voice": "af_heart", "speed": 1.0}
It answers each with the path of a WAV file, or "error <message>".
"""
import json
import os
import sys
import wave

import numpy as np
from kokoro_onnx import Kokoro

here = os.path.dirname(os.path.abspath(__file__))
kokoro = Kokoro(os.path.join(here, "kokoro-v1.0.onnx"), os.path.join(here, "voices-v1.0.bin"))
out_dir = os.path.expanduser("~/Library/Caches/LotusVoice")
os.makedirs(out_dir, exist_ok=True)
print("ready", flush=True)

for n, line in enumerate(sys.stdin):
    try:
        req = json.loads(line)
        samples, rate = kokoro.create(req["text"], voice=req.get("voice", "af_heart"),
                                      speed=float(req.get("speed", 1.0)), lang="en-us")
        path = os.path.join(out_dir, f"say-{n % 2}.wav")  # alternate files so one can play while the next is written
        pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(pcm.tobytes())
        print(path, flush=True)
    except Exception as e:  # keep serving; Lotus falls back to the system voice for this line
        print("error " + str(e).replace("\n", " "), flush=True)
