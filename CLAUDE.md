# Installing Lotus for someone

If a person asks you to install, set up or try Lotus from this repository, do this for them.

1. **Check the computer.** Run `uname -s` and `sw_vers -productVersion`.
   - Not macOS (Windows, Linux): tell them kindly that Lotus is Mac-only for now and stop.
   - macOS older than 14: tell them they need macOS 14 (Sonoma) or later and stop.
2. **Get the code** if you aren't already inside it:
   `git clone https://github.com/rohitjha138/lotus-companion.git ~/lotus-companion && cd ~/lotus-companion`
   (use the URL they gave you).
3. **Install:** run `./install.sh --extras` (about 0.6 GB: app, natural voice, video tools, GitHub CLI,
   connectors). If they only want the app, run `./install.sh`. Offer `./install.sh --all` only if they ask
   for offline image generation, and say first that it downloads about 13 GB.
   - If it says Apple's developer tools are needed, tell them to click **Install** in the window that
     appeared, wait until it finishes, then run `./install.sh --extras` again.
   - `signing-setup.sh` creates a private code-signing certificate in their login keychain so macOS keeps
     Lotus's permissions across updates. Tell them it may ask for their login password once.
4. **Walk them through the parts only they can do** (you can't click these for them):
   - Menu bar lotus › **Sign in to Claude…** with their own Claude account.
   - Allow **Microphone**, **Speech Recognition**, **Screen Recording** (then *Quit & Reopen*) and
     **Accessibility**. Menu bar lotus › **Check permissions…** shows what's still missing.
   - Optional: sign in to connectors they want (Lotus window › Connections › Connect or sign in, then `/mcp`).
5. **Finish** by telling them: say "Hey Buddy", or click Lotus in the Dock to chat. Point them to
   [PRIVACY.md](PRIVACY.md) for what stays on their Mac.

To remove it later: menu bar lotus › **Uninstall Lotus…**, or `./uninstall.sh`.

# Working on this code

- The whole app is `Sources/Lotus/main.swift`. Build and self-test with `./build.sh` (or
  `swift build && .build/debug/Lotus --selftest`); `./build.sh --install` installs and relaunches it.
- `./package.sh` makes `build/Lotus.dmg` for a release.
- Never commit anything from `~/Lotus` (a user's memory, conversations and instructions live there).
