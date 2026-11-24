# Privacy & security

Lotus is built so you can trust it with your Mac. This page says exactly what it keeps, what it sends,
and what it can never touch.

## What stays on your Mac

| What | Where |
|---|---|
| Memory of you (ideas, goals, preferences) | `~/Lotus/memory.md` |
| Every conversation, as readable text | `~/Lotus/Conversations/` |
| Your standing instructions | `~/Lotus/instructions.md` |
| Its voice (Kokoro model, runs offline) | `~/Lotus/voice/` |
| Settings | macOS preferences (`defaults read dev.ember.companion`) |

The `~/Lotus` folder is readable by your macOS account only. Your speech is turned into text on the Mac
(Apple's on-device recognition is required; Lotus won't fall back to Apple's servers). Lotus's own voice is
generated on the Mac. Screenshots are taken only when you ask about your screen and deleted as soon as
the answer arrives. Nothing is synced anywhere by Lotus.

## What leaves your Mac

- **Your request, and whatever Claude needs to answer it** (a file it reads, a screenshot you asked
  about, web results) go to **Anthropic**, under your own Claude account, because that's where Claude
  runs. Anthropic's privacy policy applies to that. If something must never leave your Mac, don't ask
  Lotus about it.
- **Connectors you sign in to** (for example Scite or Airtable) receive what you ask them for, only when
  you name them in a request.
- **Phone access**, if you turn it on, goes through your Claude account (Claude Code Remote Control). No
  ports are opened.
- **Nothing else.** Lotus has no analytics, no accounts of its own and no server. It turns off Claude
  Code's telemetry and error reporting.

## What Lotus can never do

These are blocked in code, whatever mode it runs in:

- Read your keychain, SSH, GPG or AWS keys, `.env` files, browser cookies, Messages, Mail, or Claude's
  own login files.
- Run `security`, `curl`, `scp` or `rm`.

It is also instructed never to send messages or email, post, buy, pay, delete files, submit forms or
change settings unless you asked for exactly that.

## Safety mode

By default Lotus runs Claude Code in **auto** mode: everyday actions go ahead, and Claude Code's own safety
check blocks risky ones. You can switch to *No limits* in the menu bar; the blocks above still apply.

## Things to know

- Lotus can't tell voices apart: anyone near your Mac who says "Hey Buddy" can ask it something. Mute
  it (menu bar lotus › Mute microphone) when that matters.
- Conversations are stored as plain text. Keep FileVault on (System Settings › Privacy & Security) so
  they're encrypted on disk.
- Everything is removable: menu bar lotus › **Uninstall Lotus…** deletes all of the above and resets
  every permission you gave it.

## Reporting a problem

Found a security or privacy issue? Please open a private security advisory on the GitHub repository
(Security › Report a vulnerability) rather than a public issue.
