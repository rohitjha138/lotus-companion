"""Professional image generation for Lotus, through a local ComfyUI (nothing leaves the Mac).

  python3 image.py "prompt" [--negative "..."] [--width 1024] [--height 1024] [--count 1]
                   [--steps 30] [--seed N] [--out ~/Pictures/Lotus/name.png]

Uses the SDXL checkpoint in ComfyUI (RealVisXL V5 if present). Starts ComfyUI if it isn't running and
stops it again afterwards (to free memory) unless --keep is given. Prints the saved file paths.
Set LOTUS_COMFYUI to point at another ComfyUI folder (default ~/Lotus/ComfyUI, made by extras.sh --images).
"""
import argparse
import json
import os
import random
import shutil
import subprocess
import sys
import time
import urllib.request

COMFY = os.path.expanduser(os.environ.get("LOTUS_COMFYUI") or next(
    (p for p in ("~/Lotus/ComfyUI", "~/video-tools/ComfyUI") if os.path.isdir(os.path.expanduser(p))), "~/Lotus/ComfyUI"))
URL = "http://127.0.0.1:8188"


def call(path, body=None):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def running():
    try:
        call("/system_stats")
        return True
    except Exception:
        return False


def start():
    python = os.path.join(COMFY, ".venv/bin/python")
    if not os.path.exists(python):
        sys.exit(f"ComfyUI not found at {COMFY}")
    log = open(os.path.expanduser("~/Library/Logs/Lotus-comfyui.log"), "w")
    proc = subprocess.Popen([python, "main.py", "--listen", "127.0.0.1", "--port", "8188"], cwd=COMFY,
                            stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "PYTORCH_ENABLE_MPS_FALLBACK": "1"})
    for _ in range(180):
        if running():
            return proc
        if proc.poll() is not None:
            sys.exit("ComfyUI failed to start; see ~/Library/Logs/Lotus-comfyui.log")
        time.sleep(1)
    proc.terminate()
    sys.exit("ComfyUI took too long to start")


def checkpoint():
    folder = os.path.join(COMFY, "models/checkpoints")
    found = sorted(f for f in os.listdir(folder) if f.endswith((".safetensors", ".ckpt")))
    if not found:
        sys.exit("No checkpoint in ComfyUI/models/checkpoints")
    return next((f for f in found if "realvis" in f.lower()), found[0])


def workflow(a, seed):
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": checkpoint()}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": a.prompt, "clip": ["1", 1]}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": a.negative, "clip": ["1", 1]}},
        "4": {"class_type": "EmptyLatentImage", "inputs": {"width": a.width, "height": a.height, "batch_size": 1}},
        "5": {"class_type": "KSampler", "inputs": {
            "model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0], "latent_image": ["4", 0],
            "seed": seed, "steps": a.steps, "cfg": a.cfg, "sampler_name": "dpmpp_2m_sde",
            "scheduler": "karras", "denoise": 1.0}},
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": "lotus"}},
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("prompt")
    p.add_argument("--negative", default="blurry, low quality, jpeg artifacts, deformed, distorted, extra fingers, watermark, text, logo")
    p.add_argument("--width", type=int, default=1024)
    p.add_argument("--height", type=int, default=1024)
    p.add_argument("--steps", type=int, default=30)
    p.add_argument("--cfg", type=float, default=5.0)
    p.add_argument("--count", type=int, default=1)
    p.add_argument("--seed", type=int)
    p.add_argument("--out", default="~/Pictures/Lotus/lotus.png")
    p.add_argument("--keep", action="store_true", help="leave ComfyUI running afterwards")
    a = p.parse_args()

    proc = None if running() else start()
    try:
        out = os.path.expanduser(a.out)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        stem, ext = os.path.splitext(out)
        for i in range(a.count):
            seed = a.seed + i if a.seed is not None else random.randint(0, 2**32 - 1)
            prompt_id = call("/prompt", {"prompt": workflow(a, seed)})["prompt_id"]
            while True:
                history = call(f"/history/{prompt_id}").get(prompt_id)
                if history and history.get("outputs"):
                    break
                if history and history.get("status", {}).get("status_str") == "error":
                    sys.exit("Generation failed; see ~/Library/Logs/Lotus-comfyui.log")
                time.sleep(1)
            img = history["outputs"]["7"]["images"][0]
            src = os.path.join(COMFY, "output", img.get("subfolder", ""), img["filename"])
            dest = out if a.count == 1 else f"{stem}-{i + 1}{ext}"
            n = 2
            while os.path.exists(dest):  # never overwrite
                dest = f"{os.path.splitext(dest)[0]}-{n}{ext}"
                n += 1
            shutil.move(src, dest)
            print(dest, flush=True)
    finally:
        if proc and not a.keep:
            proc.terminate()


if __name__ == "__main__":
    main()
