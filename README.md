<p align="center"><img src="icon/logo.png" width="160" alt="Lotus logo"></p>

<h1 align="center">Lotus</h1>

<p align="center"><b>A voice companion that lives on your Mac, powered by Claude.</b><br>
Say “Hey Buddy”, ask anything, and it answers out loud, sees your screen, and gets the work done.</p>

---

## Install it with Claude (easiest)

Open the **Claude desktop app → Code** (or Claude Code in a terminal) on your Mac and paste:

> Install Lotus for me from https://github.com/rohitjha138/lotus-companion

Claude clones this repo, runs the installer, and walks you through signing in and the few macOS
permissions only you can click. About five minutes. Lotus is Mac-only for now (macOS 14 or later).

<details>
<summary>Or install it yourself in Terminal</summary>

```bash
git clone https://github.com/rohitjha138/lotus-companion.git && cd lotus-companion && ./install.sh --extras
```

`--extras` adds the natural voice, video tools, GitHub CLI and connectors (about 0.6 GB). Leave it off for
just the app; use `--all` to add offline image generation too (about 13 GB more). Then click the lotus in
the menu bar › **Sign in to Claude…** and allow the permissions macOS asks for.
</details>

---

## What it is

Lotus is a small pink-and-white lotus flower with a face that sits in the corner of your screen. Its eyes
follow your cursor; its petals open when it listens and fold shut when it sleeps. Talk to it or type to
it, and it uses Claude to answer questions, research, control your apps, find and read files, edit
video, make images, and keep your schedule.

Your memory, conversations, settings and voice stay on your Mac. Everyone signs in with their own Claude
account, so every Lotus is its owner's alone.

| | |
|---|---|
| **Talk naturally** | “Hey Buddy” (or “Hey there”), then just speak. It waits for you to finish, and you can reply without the wake word for a few seconds after it answers. Tap the lotus to talk or to stop it. |
| **Chat window** | Click Lotus in the Dock to type instead, drop in photos or files, read past conversations, see connections and edit your instructions. |
| **See your screen** | “Look at my screen, what's wrong here?” takes one screenshot, answers, then deletes it. |
| **Act for you** | Opens and controls apps, clicks and types, plays music, works in your own Chrome (LinkedIn, Gmail, Docs) through the Claude in Chrome extension. |
| **Research** | Several sources cross-checked, answer first. Papers from PubMed, Europe PMC, arXiv, OpenAlex and Semantic Scholar; Scite and Hugging Face through connectors. |
| **Personal assistant** | Events and reminders in Apple Calendar and Reminders (synced to your iPhone), a run-through of your day, finds and opens files. |
| **Create** | Edits video with ffmpeg and auto-editor; makes professional photos and sketches offline with ComfyUI and RealVisXL. |
| **Remembers you** | A small private memory file it keeps up to date, plus a readable history of every conversation. |
| **Your instructions** | Tell it once how you like things done; it follows them every time. |
| **From your phone** | Phone access lets the Claude app reach your Mac through your Claude account. |
| **Sounds human** | A natural voice (Kokoro) that runs offline. Sweet or deep. |

## Why I built it

I built Lotus part-time, out of frustration. I wanted a companion for my own projects that I could just
talk to: one that remembers what I'm working on, sees what I'm looking at and does the boring parts for
me, without handing my data to yet another service. So I made one, and I'm sharing it so anyone can have
their own.

The lotus is inspired by my girlfriend.

— Voyager

## Privacy

Everything Lotus keeps is on your Mac, in a folder only you can read. Your speech is turned into text on
the Mac, and Lotus's voice is generated on the Mac. What leaves: your request, and whatever Claude needs
to answer it, goes to Anthropic, because that's where Claude runs. Secrets (keychain, SSH and cloud keys,
messages, mail, browser cookies, `.env` files) are blocked, and there's no tracking.

Full details: **[PRIVACY.md](PRIVACY.md)**.

## Using it

- **Talk:** “Hey Buddy, what's on my calendar today?”, “Hey Buddy, look at my screen”, “Hey Buddy, play
  something chill”, “Hey Buddy, find the PDF I downloaded yesterday and summarise it”.
- **Type:** click Lotus in the Dock. Drag photos or files into the chat to ask about them.
- **Menu bar lotus:** mute, voice style (cute or deep), phone access, open at login, what Lotus remembers,
  conversation history, check permissions, sign in or out, uninstall.
- **Connectors:** Lotus loads a Claude connector only when you name it (“search Scite for…”, “add this to
  my Airtable”), so everyday answers stay fast. Sign in to each once from Lotus › Connections (type `/mcp`).

<details>
<summary><b>Settings</b></summary>

```bash
defaults write dev.ember.companion permissionMode auto        # auto (default) or bypassPermissions
defaults write dev.ember.companion pauseSeconds 2.2           # how long a pause ends what you're saying
defaults write dev.ember.companion nudgeMinutes 60            # how often it says hi
defaults write dev.ember.companion kokoroVoice af_bella       # af_heart (default), af_bella, bf_emma, am_michael…
defaults write dev.ember.companion model sonnet               # default: haiku, sonnet for bigger jobs
defaults write dev.ember.companion locale en-GB               # speech language
```

Restart Lotus after changing them.
</details>

<details>
<summary><b>How it works</b></summary>

```
"Hey Buddy …" ─► Apple Speech (on-device) ─┐
chat window / dropped files ───────────────┼─► claude -p (your account) ─► reply
screenshot, only when asked ───────────────┘       │
                                                    ├─► Kokoro voice (on-device) + speech bubble
                                                    └─► ~/Lotus/Conversations (plain text)
```

Each request runs Claude Code headless with a short persona, your memory and instructions, and only what
it needs: browser control for web tasks, a connector when you name it, the stronger model for big jobs.
The whole app is one Swift file, [`Sources/Lotus/main.swift`](Sources/Lotus/main.swift).
</details>

## Develop

```bash
./build.sh            # build and run the self-test
./build.sh --install  # install to /Applications and relaunch
./package.sh          # make build/Lotus.dmg
```

## Storage and uninstall

About 0.5 GB with the voice; the app itself is under 2 MB. Everything Lotus stores is capped or pruned, so
it can run for years without filling your disk. **Menu bar lotus › Uninstall Lotus…** (or
`./uninstall.sh`) removes the app, its data, its certificate and every permission you gave it. Your Claude
sign-in is kept.

## License

MIT © 2026 Voyager. See [LICENSE](LICENSE). Lotus is an independent project, not made by or affiliated
with Anthropic. Claude is a trademark of Anthropic.

## Credits

Built on [Claude Code](https://claude.com/claude-code). Voice: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
(Apache 2.0) via [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) (MIT). Images:
[ComfyUI](https://github.com/comfyanonymous/ComfyUI) (GPL-3.0) with
[RealVisXL V5](https://huggingface.co/SG161222/RealVisXL_V5.0). Video:
[auto-editor](https://github.com/WyattBlue/auto-editor), [ffmpeg](https://ffmpeg.org) and
[yt-dlp](https://github.com/yt-dlp/yt-dlp). All are downloaded by the installers, not stored in this repo.
