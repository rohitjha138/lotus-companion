// Lotus — a voice companion that lives on your Mac, powered by Claude.
// Copyright (c) 2026 Voyager. MIT License (see LICENSE). Original work; the lotus is for someone dear.
// Project: https://github.com/rohitjha138/lotus-companion
import AppKit
import AVFoundation
import ServiceManagement
import Speech
import SwiftUI
import UniformTypeIdentifiers

let defaults = UserDefaults.standard
let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - Understanding what was said

// "Hey Buddy" (or "Hey there") wakes it. Not "Claude", so talking to the Claude app doesn't trigger it.
// Recognisers sometimes hear "buddy" as "body"/"bud e"; bare "buddy" alone is too common, so it needs a greeting.
let wakeWords = ["hey buddy", "hi buddy", "ok buddy", "okay buddy", "hey body", "hey bud e", "hey there"]

/// Text spoken after the most recent wake word, or nil if no wake word was heard.
func command(after transcript: String) -> String? {
    let text = transcript.lowercased()
    let hits = wakeWords.compactMap { text.range(of: $0, options: .backwards) }
    guard let last = hits.max(by: { $0.upperBound < $1.upperBound }) else { return nil }
    return clean(String(text[last.upperBound...]))
}

func clean(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
}

/// The screen is only captured when you ask about it.
func wantsScreen(_ request: String) -> Bool {
    let r = request.lowercased()
    return ["screen", "look at", "see this", "see what", "what's this", "what is this", "this error", "on my display",
            "what am i looking at", "click", "tap", "press the", "this window", "this page", "scroll",
            "can you see", "do you see", "this question", "this photo", "this picture", "this image", "answer this", "what's going on", "what is going on", "read this"]
        .contains { r.contains($0) }
}

/// Jobs on websites go through the user's own Chrome (Claude in Chrome extension), with their logins.
func needsBrowser(_ request: String) -> Bool {
    let r = request.lowercased()
    return ["linkedin", "email", "e-mail", "gmail", "inbox", "outlook", "instagram", "facebook", "twitter", "x.com",
            "whatsapp web", "youtube", "website", "web page", "webpage", "browser", "chrome", "google docs",
            "google sheets", "google drive", "reply to", "messages", "post on", "online", "sign up", "log in"]
        .contains { r.contains($0) }
}

/// Bigger jobs get the stronger model; quick chat and simple commands stay on the fast one.
func isBigTask(_ request: String) -> Bool {
    let r = request.lowercased()
    return r.split(separator: " ").count > 18 ||
        ["edit", "video", "create", "make a", "make me", "write", "build", "organi", "research", "summar", "convert",
         "fix", "analy", "plan", "design", "code", "document", "presentation", "spreadsheet", "compare", "explain", "teach",
         "image", "photo", "picture", "sketch", "draw", "paper", "caption"]
        .contains { r.contains($0) }
}

func selfTest() {
    precondition(command(after: "what time is it") == nil)
    precondition(command(after: "Claude, open Safari") == nil)
    precondition(command(after: "my buddy is here") == nil)
    precondition(command(after: "Hey Buddy") == "")
    precondition(command(after: "Hey buddy, open Safari.") == "open safari")
    precondition(command(after: "um hey there what's the weather") == "what's the weather")
    precondition(command(after: "hey buddy stop. Hey Buddy play music") == "play music")
    precondition(wantsScreen("look at my screen and fix this"))
    precondition(wantsScreen("tap the blue button"))
    precondition(wantsScreen("can you see it, what's the answer to this question"))
    precondition(!wantsScreen("play some music"))
    precondition(isBigTask("edit these videos into one clip"))
    precondition(!isBigTask("play shape of you"))
    precondition(needsBrowser("reply to my LinkedIn messages"))
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("lotus-selftest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    Transcript.add(you: "hi", lotus: "Hi!", at: Date(timeIntervalSince1970: 1_700_000_000), in: scratch)
    Transcript.add(you: "bye", lotus: "Bye!", at: Date(timeIntervalSince1970: 1_700_000_100), in: scratch)
    Transcript.add(you: "later", lotus: "Hello again", at: Date(timeIntervalSince1970: 1_710_000_000), in: scratch)
    let logged = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
    precondition(logged.count == 2)  // two different months
    let first = (try? String(contentsOf: scratch.appendingPathComponent(logged.sorted()[0]), encoding: .utf8)) ?? ""
    precondition(first.contains("You:** hi") && first.contains("Lotus:** Bye!"))
    Transcript.trim(limit: 10, in: scratch)
    precondition(((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).count == 1)
    precondition(!needsBrowser("what time is it"))
    precondition(Agent.mentions("find papers on Hugging Face", connector: "hugging-face"))
    precondition(Agent.mentions("make clips with Opus Clip", connector: "opusclip"))
    precondition(!Agent.mentions("open my notes", connector: "airtable"))
    precondition(Pointer.toPoints(pixelX: 200, pixelY: 100, scale: 2) == CGPoint(x: 100, y: 50))
    precondition(Agent.parse(#"{"type":"result","result":"Done!","session_id":"abc"}"#) == ("Done!", "abc"))
    precondition(Agent.parse("not json").1 == nil)
    print("self-test passed")
}

// MARK: - Hands: clicking for Claude

/// `Lotus --click X Y [--double|--right]` clicks the main display at pixel coordinates from a
/// screenshot. Claude Code runs this; macOS asks once for Accessibility permission.
enum Pointer {
    static func toPoints(pixelX: Double, pixelY: Double, scale: Double) -> CGPoint {
        CGPoint(x: pixelX / scale, y: pixelY / scale)
    }

    static func run(_ args: [String]) -> Never {
        guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
            print("usage: Lotus --click X Y [--double|--right]   (pixel coordinates from a screenshot of the main display)")
            exit(2)
        }
        guard AXIsProcessTrusted() else {
            print("Lotus needs Accessibility permission: System Settings › Privacy & Security › Accessibility › Lotus")
            exit(1)
        }
        let display = CGMainDisplayID()
        let scale = CGDisplayCopyDisplayMode(display).map { Double($0.pixelWidth) / Double($0.width) } ?? 2
        let point = toPoints(pixelX: x, pixelY: y, scale: scale)
        let right = args.contains("--right")
        let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        let button: CGMouseButton = right ? .right : .left
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        usleep(80_000)
        for click in 1...(args.contains("--double") ? 2 : 1) {
            for type in [down, up] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                event?.post(tap: .cghidEventTap)
                usleep(40_000)
            }
        }
        print("clicked \(Int(point.x)),\(Int(point.y)) (points)")
        exit(0)
    }
}

// MARK: - Claude Code

enum Agent {
    static let lotus = Bundle.main.executablePath ?? "/Applications/Lotus.app/Contents/MacOS/Lotus"
    static let cache = home.appendingPathComponent("Library/Caches/Lotus")
    static let resources = Bundle.main.resourcePath ?? "/Applications/Lotus.app/Contents/Resources"

    static var persona: String { """
    You are Lotus, the user's sharp, warm companion on their Mac, talking with them by voice. Be brief and \
    quick-witted: use as few words as possible, usually one short sentence. When a task is done, just say so, \
    like "Done." or "Done, Safari's closed." Never narrate your steps, explain your reasoning or add extra \
    detail unless asked. Only go longer when they ask you to teach or explain something, and even then keep \
    each step short and check they're with you. Greet them back in a few friendly words. Everything you \
    write is spoken aloud: no markdown, lists, code or URLs. Act fast: take the most direct route.

    Questions versus actions: when the user asks a question, just answer it, straight away. Don't take \
    actions they didn't ask for, and don't search their files or the web unless the answer truly needs it. \
    When they ask you to do something (play, open, write, edit, send to a file), do exactly that, fully, \
    end to end, without asking them questions: pick the most likely meaning and go. Save results next to \
    the originals with clear names and say in one sentence where they are. If something fails, try \
    another way before giving up.

    Research, like a top answer engine: for anything that needs current or factual information, search \
    several sources, cross-check them, give the answer first in a sentence or two, then name the key \
    source. For science and biotech use primary sources first (PubMed, Europe PMC, bioRxiv, Google \
    Scholar, journal sites) and mention the paper and year.

    Video, like a professional editor: ffmpeg, ffprobe, auto-editor (removes silences and dead air) and \
    yt-dlp are installed. Check the footage with ffprobe first, then cut cleanly, remove silences, \
    normalise loudness (ffmpeg loudnorm), keep the best quality, add fades, captions or music when it \
    fits, and export H.264 MP4 unless asked otherwise. Never overwrite the originals.

    Listening: the user's words come through speech recognition and may contain misheard words, missing \
    punctuation or mixed languages. Quietly work out what they meant and act on that; don't point out \
    the mistakes. Only correct the user's grammar, pronunciation or language when they ask you to, and \
    then show the corrected sentence and briefly why.

    Images, like a professional photographer and illustrator: generate them locally with \
    python3 "\(resources)/image.py" "PROMPT" --out ~/Pictures/Lotus/NAME.png (options: --width/--height, \
    e.g. 832x1216 portrait or 1216x832 landscape, --count N, --negative "..."). It uses ComfyUI with the \
    RealVisXL model and takes one to two minutes, so tell the user it's on its way. Write prompts like a pro: \
    subject, setting, composition, lens and focal length, lighting, mood, colour palette and style. For \
    sketches say pencil or ink sketch, graphite, cross-hatching, on paper, and drop "sketch" from the \
    negative prompt. Open the result with open when done. When asked for photo advice, give concrete \
    tips on composition, light, posing and editing.
    More media tools in ~/video-tools (see its README.md): whisper.cpp for captions and transcripts, \
    LivePortrait to animate a photo, Remotion for motion graphics, MoviePy.

    GitHub: the gh command is installed; use it for repos, issues and pull requests (if it says to log in, \
    tell the user to run gh auth login once).
    Connected services: when the user names one of their Claude connectors (for example Scite for \
    citation-backed research, Hugging Face for models, datasets and papers, Airtable, Adobe Workfront, \
    OpusClip for short clips, Jasper for on-brand writing), its tools are loaded for that request: use them. \
    If one says it needs signing in, tell the user to open Lotus › Connections › Connect or sign in.

    Scholarly search: use these free APIs with web fetch for papers: api.openalex.org/works?search=, \
    api.semanticscholar.org/graph/v1/paper/search?query=...&fields=title,year,authors,abstract,url, \
    eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term= (PubMed), \
    www.ebi.ac.uk/europepmc/webservices/rest/search?query=...&format=json, export.arxiv.org/api/query?search_query=.

    Writing: write in the user's own voice (use your memory of them). When asked, proofread and correct \
    grammar, clarity and flow. When asked to make writing sound more natural or human, vary sentence length, \
    cut filler and stock phrases, and keep their meaning and facts.

    Apps and browser: control native apps with AppleScript and clicks. For websites (LinkedIn, Gmail, \
    Outlook, Instagram, YouTube, Google Docs and so on), use the Claude in Chrome tools when you have \
    them: they work in the user's own Chrome where they're already signed in. Keep going until the job \
    is finished. Send, post or reply only when the user asked you to, and then do it.
    Personal assistant: keep the user's schedule and reminders in Apple Calendar and Reminders with \
    osascript (they stay in their Apple account and sync to their iPhone). Add events and reminders with \
    the right date and time, read out today's or tomorrow's plan, and move or cancel things when asked. \
    Reminders you set notify them on their own. To find files use mdfind; when you find what they wanted, \
    open it with open so they can see it, and give the answer in a sentence.
    Music: to play a song, find its open.spotify.com/track/ID with web search, then run \
    osascript -e 'tell application "Spotify" to play track "spotify:track:ID"'. Play it straight away.

    You can act on the Mac:
    - Research: use web search and fetch to look things up on different websites and give the answer.
    - Apps: osascript (AppleScript / System Events) to control apps and type; open to launch apps, files and links.
    - Files: mdfind and Glob to find files, Read to read them.
    - Screen: a screenshot path may be given; Read it to see the screen. To look again after acting, run \
    screencapture -x -m \(cache.path)/look.png and Read it.
    - Clicking: run \(lotus) --click X Y using pixel coordinates from the screenshot (add --double or --right).
    - Typing: osascript -e 'tell application "System Events" to keystroke "text"' (key code 36 is Return).

    Be their tutor and research partner in whatever they're learning: teach step by step, quiz them \
    gently, explain papers and methods, find current research, and build on their own ideas instead of \
    replacing them. Learn alongside them.

    Memory: \(memory.path) is your private memory of this user, kept only on this Mac. When they tell you \
    an idea, a goal, a preference, something about themselves, or what they've learned, add a short dated \
    line to the right section of that file with Edit (create it if missing). Keep it small, under about 6 KB: \
    update or merge instead of repeating, and remove things that are outdated or no longer true, but never \
    drop the user's ideas unless they ask. Never store passwords or secrets there.
    The user's work and past chats: their projects are folders in \(home.path)/Claude (if it exists; for \
    example a research project or a coursework assignment). Summaries of earlier Claude sessions are in \
    \(home.path)/.claude/wrap-ups, and full transcripts of their Claude Code chats are the .jsonl files in \
    \(home.path)/.claude/projects (large: Grep them for keywords, then read only the matching lines). When \
    they mention a project, an assignment or something "we" did, look there first (folder names, README, \
    CLAUDE.md, recent files) so you know what they mean, then answer. Their claude.ai web chats aren't on \
    this Mac; say so if that's where it was.
    Photos and files: "look at this photo" usually means what's on screen; if the screenshot doesn't \
    show it, check files they attached, then the newest images in Downloads, Desktop and Pictures.

    Past conversations: every exchange is saved in \(Transcript.folder.path), one Markdown file per month \
    (like 2026-11.md, each entry dated). When the user asks what you talked about, what they told you \
    before, or to pick something back up, Grep or Read those files and answer from them, so they never \
    have to repeat themselves.
    What you remember so far:
    \(rememberedText)
    \(customInstructions)

    Respect the user's privacy and dignity. Never send messages or emails, post, buy, pay, delete files, \
    submit forms or change settings unless they asked for exactly that. Never read or repeat passwords, \
    keys or other secrets. Never quit, kill or close Lotus (yourself) or Claude. Do what was asked, then say briefly what you did or found.
    """ }

    static let memory = home.appendingPathComponent("Lotus/memory.md")
    static let instructions = home.appendingPathComponent("Lotus/instructions.md")

    /// The user's own standing instructions, edited in the app's Instructions tab.
    static var customInstructions: String {
        let text = ((try? String(contentsOf: instructions, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : "\nThe user's own standing instructions (follow them; spoken replies still stay short):\n" + String(text.prefix(8_000))
    }

    static var rememberedText: String {
        let text = (try? String(contentsOf: memory, encoding: .utf8)) ?? ""
        return text.isEmpty ? "(nothing yet)" : String(text.suffix(12_000))  // shortcut: newest 12k chars; summarise the file if it grows past that
    }

    static func ensureMemory() {
        // Privacy: Lotus's folder (memory, conversations, instructions, voice) is readable by you alone.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: memory.deletingLastPathComponent().path)
        guard !FileManager.default.fileExists(atPath: memory.path) else { return }
        try? FileManager.default.createDirectory(at: memory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? """
        # What Lotus knows about me
        Private to this Mac. Edit freely; Lotus reads it before every answer.

        ## About me

        ## My ideas

        ## Biotechnology: what I'm learning

        ## Preferences

        """.write(to: memory, atomically: true, encoding: .utf8)
    }

    // A safe-ish default. Change it with: defaults write dev.ember.companion allowedTools "..."
    static var defaultTools: String {
        "Read,Glob,Grep,WebSearch,WebFetch,Write,Edit,Bash(osascript:*),Bash(open:*),Bash(mdfind:*),Bash(ls:*)," +
        "Bash(date:*),Bash(pmset:*),Bash(screencapture:*),Bash(\(lotus) --click:*),mcp__claude-in-chrome"
    }

    // Never readable by Lotus, whatever the allow list says.
    static let privateTools = "Read(~/.ssh/**),Read(~/.gnupg/**),Read(~/.aws/**),Read(~/Library/Keychains/**)," +
        "Read(~/Library/Messages/**),Read(~/Library/Mail/**),Read(~/Library/Cookies/**),Read(~/.claude.json)," +
        "Read(~/.claude/.credentials.json),Read(~/.claude/settings*.json),Read(**/.env)," +
        "Bash(security:*),Bash(curl:*),Bash(scp:*),Bash(rm:*)"

    static let claudePath: String? = {
        if let path = defaults.string(forKey: "claudePath") { return path }
        // GUI apps get a bare PATH, so ask the user's login shell where claude lives.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-ilc", "command -v claude"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        try? shell.run()
        shell.waitUntilExit()
        let found = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").last { $0.hasPrefix("/") }.map(String.init)
        if let found { return found }
        // Fallback: the copy bundled with the Claude desktop app.
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let enumerator = FileManager.default.enumerator(at: bundled, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.path.hasSuffix("Contents/MacOS/claude") { return url.path }
        }
        return nil
    }()

    static func environment(for claude: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // An npm-installed claude needs node on PATH.
        let dir = (claude as NSString).deletingLastPathComponent
        env["PATH"] = "\(dir):\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        // Privacy: no telemetry, error reports or other non-essential traffic from Claude Code.
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["DISABLE_TELEMETRY"] = "1"
        env["DISABLE_ERROR_REPORTING"] = "1"
        return env
    }

    static func parse(_ output: String) -> (String, String?) {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let tail = output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)
            return (tail.isEmpty ? "Something went wrong talking to Claude Code." : String(tail), nil)
        }
        let reply = (json["result"] as? String) ?? "Done."
        return (reply, json["session_id"] as? String)
    }

    /// Saves the main display to a private cache file inside your home folder.
    static func captureScreen() -> URL? {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("screen-\(UUID().uuidString).png")
        let shot = Process()
        shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        shot.arguments = ["-x", "-m", file.path]  // shortcut: main display only; pass one path per display to capture all
        try? shot.run()
        shot.waitUntilExit()
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Your Claude Code connectors (from ~/.claude.json). Loading them costs seconds, so a request gets only
    /// the ones it names ("search Scite for…", "my Airtable base"), or all of them when switched on.
    static func connectorsFor(_ request: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = config["mcpServers"] as? [String: Any] else { return [:] }
        if defaults.bool(forKey: "useConnectors") { return servers }
        return servers.filter { mentions(request, connector: $0.key) }
    }

    /// True when the request names the connector, ignoring spaces, dashes and case ("Hugging Face" = hugging-face).
    static func mentions(_ request: String, connector: String) -> Bool {
        let squash = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let name = squash(connector)
        return name.count >= 4 && squash(request).contains(name)
    }

    /// The request being worked on, so a tap can stop it.
    static var current: Process?

    /// Runs one headless Claude Code turn. `done` is called on the main thread.
    static func run(_ request: String, session: String?, withScreen: Bool, done: @escaping (String, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let finish = { (reply: String, id: String?) in DispatchQueue.main.async { done(reply, id) } }
            guard let claude = claudePath else {
                return finish("I can't find Claude Code. Install it from claude.com/claude-code, then restart me.", nil)
            }
            var prompt = request
            let screenshot = withScreen ? captureScreen() : nil
            defer { try? FileManager.default.removeItem(at: cache) }  // never keep any screenshot
            if let screenshot {
                prompt += "\n\n(A screenshot of my screen right now is at \(screenshot.path). Read it to see what I see.)"
            }

            // Speed: skip the user's own Claude Code plugins, hooks and connectors (they add seconds and
            // coding-mode instructions), use a fast model, and keep thinking short.
            let browser = needsBrowser(request)
            let heavy = withScreen || browser || isBigTask(request) || !connectorsFor(request).isEmpty
            let model = defaults.string(forKey: "model") ?? (heavy ? "sonnet" : "haiku")
            var args = ["-p", "--output-format", "json", "--append-system-prompt", persona,
                        "--settings", #"{"disableAllHooks":true}"#,
                        "--model", model, "--effort", heavy ? "medium" : "low", "--add-dir", home.path,
                        "--permission-mode", defaults.string(forKey: "permissionMode") ?? "auto",
                        "--allowedTools", defaults.string(forKey: "allowedTools") ?? defaultTools,
                        "--disallowedTools", privateTools]
            if browser { args.append("--chrome") }
            // Your Claude Code connectors load only when named (or all when switched on): they cost seconds per request.
            args += ["--strict-mcp-config", "--setting-sources", "project"]
            let connectors = connectorsFor(request)
            if !connectors.isEmpty, let json = try? JSONSerialization.data(withJSONObject: ["mcpServers": connectors]) {
                args += ["--mcp-config", String(decoding: json, as: UTF8.self)]
            }
            if let session { args += ["--resume", session] }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: claude)
            proc.arguments = args
            ensureMemory()
            proc.currentDirectoryURL = memory.deletingLastPathComponent()  // ~/Lotus, so no project settings load
            proc.environment = environment(for: claude)
            let input = Pipe(), output = Pipe()
            proc.standardInput = input  // prompt goes via stdin so it can't be mistaken for a flag value
            proc.standardOutput = output
            proc.standardError = output
            do { try proc.run() } catch { return finish("I couldn't start Claude Code: \(error.localizedDescription)", nil) }
            DispatchQueue.main.async { current = proc }
            input.fileHandleForWriting.write(Data(prompt.utf8))
            try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let (reply, id) = parse(String(decoding: data, as: UTF8.self))
            if reply.contains("Not logged in") {
                return finish("I'm not signed in yet. Click the lotus in the menu bar and choose Sign in to Claude. You only do it once.", nil)
            }
            finish(reply, id)
        }
    }
}

// MARK: - The character

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
    var files: [URL] = []
}

final class Model: ObservableObject {
    enum Mood { case sleeping, idle, waving, listening, working, speaking }
    @Published var mood = Mood.idle
    @Published var bubble = ""
    @Published var messages: [ChatMessage] = []  // this session's chat, voice and typed
    var resting: Bool { mood == .sleeping || mood == .idle || mood == .waving }
}


struct Buddy: View {
    @ObservedObject var model: Model
    var look: () -> CGPoint     // where you are relative to Lotus, each axis -1...1
    var onTap: () -> Void
    var onDrag: (Bool) -> Void  // true while dragging, false when dropped

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !model.bubble.isEmpty {
                Text(model.bubble)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(7)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.8)))
                    .frame(maxWidth: 260, alignment: .trailing)
                    .transition(.opacity)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, _ in draw(&context, t: t) }
                    .frame(width: 120, height: 96)
                    .overlay(alignment: .topTrailing) { badge(t: t) }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .gesture(DragGesture(minimumDistance: 3).onChanged { _ in onDrag(true) }.onEnded { _ in onDrag(false) })
            .help("Tap to talk, drag to move")
        }
        .frame(width: 300, height: 250, alignment: .bottomTrailing)
        .animation(.easeInOut(duration: 0.25), value: model.bubble)
    }

    /// Draws Lotus: a pink-and-white lotus with a face on its centre petal. Petals open wider when it
    /// listens, fold in when it sleeps, one waves, and the mouth moves when it talks.
    func draw(_ context: inout GraphicsContext, t: Double) {
        let mood = model.mood
        let base = CGPoint(x: 60, y: 84)
        let breathe = sin(t * (mood == .sleeping ? 1.2 : 2.4))
        let spread: Double = switch mood {
        case .sleeping: 0.55
        case .listening: 1.18
        default: 1.0
        }
        let openness = spread + breathe * 0.03

        func petal(_ length: Double, _ width: Double, _ angle: Double) -> Path {
            var p = Path()
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: 0, y: -length), control1: CGPoint(x: -width, y: -length * 0.3), control2: CGPoint(x: -width * 0.45, y: -length * 0.86))
            p.addCurve(to: .zero, control1: CGPoint(x: width * 0.45, y: -length * 0.86), control2: CGPoint(x: width, y: -length * 0.3))
            return p.applying(CGAffineTransform(rotationAngle: angle * .pi / 180).concatenating(CGAffineTransform(translationX: base.x, y: base.y)))
        }
        func fill(_ path: Path, length: Double, angle: Double, tip: Color, root: Color) {
            let rad = angle * .pi / 180
            let end = CGPoint(x: base.x + sin(rad) * length, y: base.y - cos(rad) * length)
            context.fill(path, with: .linearGradient(Gradient(colors: [root, tip]), startPoint: base, endPoint: end))
            context.stroke(path, with: .color(Color(red: 0.76, green: 0.09, blue: 0.36).opacity(0.35)), lineWidth: 0.8)
        }
        let pale = Color(red: 0.97, green: 0.65, blue: 0.76), pink = Color(red: 0.93, green: 0.25, blue: 0.48)
        let white = Color.white, blush = Color(red: 1, green: 0.95, blue: 0.97)

        // Lily pad it sits on.
        context.fill(Path(ellipseIn: CGRect(x: base.x - 42, y: base.y - 5, width: 84, height: 12)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.72, blue: 0.45), Color(red: 0.25, green: 0.5, blue: 0.3)]),
                                           startPoint: CGPoint(x: base.x, y: base.y - 5), endPoint: CGPoint(x: base.x, y: base.y + 7)))

        // Back petals, then the waving one, then the front row.
        for side in [-1.0, 1.0] { fill(petal(28, 13, side * 76 * openness), length: 28, angle: side * 76 * openness, tip: pale, root: blush) }
        let wave = mood == .waving ? sin(t * 9) * 18 : 0
        fill(petal(36, 15, -50 * openness), length: 36, angle: -50 * openness, tip: pale, root: white)
        fill(petal(36, 15, 50 * openness + wave), length: 36, angle: 50 * openness + wave, tip: pale, root: white)
        for side in [-1.0, 1.0] { fill(petal(44, 17, side * 24 * openness), length: 44, angle: side * 24 * openness, tip: pink, root: white) }
        fill(petal(52, 21, 0), length: 52, angle: 0, tip: pink, root: white)

        // Face on the centre petal.
        let ink = Color(red: 0.25, green: 0.1, blue: 0.2)
        let eyeY = base.y - 22
        let blinking = mood != .sleeping && t.truncatingRemainder(dividingBy: 4.3) < 0.15
        let gaze = mood == .working ? CGPoint(x: 0, y: 1) : look()
        for side in [-1.0, 1.0] {
            let x = base.x + side * 7
            if mood == .sleeping || blinking {
                var lid = Path()
                lid.move(to: CGPoint(x: x - 3.5, y: eyeY))
                lid.addQuadCurve(to: CGPoint(x: x + 3.5, y: eyeY), control: CGPoint(x: x, y: eyeY + 3))
                context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            } else {
                let h: Double = mood == .listening ? 9 : 7.5
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: eyeY - h / 2, width: 6, height: h)), with: .color(ink))
                let shine = CGPoint(x: x - 0.8 + gaze.x * 1.2, y: eyeY - h / 4 - gaze.y * 1.2)
                context.fill(Path(ellipseIn: CGRect(x: shine.x - 1.3, y: shine.y - 1.3, width: 2.6, height: 2.6)), with: .color(.white))
            }
            context.fill(Path(ellipseIn: CGRect(x: x + side * 3 - 3, y: eyeY + 6, width: 6, height: 3)), with: .color(pink.opacity(0.35)))
        }
        if mood == .speaking {
            let open = 1.5 + 3 * abs(sin(t * 12))
            context.fill(Path(ellipseIn: CGRect(x: base.x - 2.5, y: eyeY + 7, width: 5, height: open)), with: .color(ink))
        } else if mood != .sleeping {
            var smile = Path()
            smile.move(to: CGPoint(x: base.x - 3, y: eyeY + 7))
            smile.addQuadCurve(to: CGPoint(x: base.x + 3, y: eyeY + 7), control: CGPoint(x: base.x, y: eyeY + 10))
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // Working: a little laptop in front, with tapping.
        if mood == .working {
            let lid = CGRect(x: base.x - 15, y: base.y - 14, width: 30, height: 12)
            context.fill(Path(roundedRect: lid, cornerRadius: 1.5), with: .color(Color(white: 0.85)))
            context.fill(Path(roundedRect: CGRect(x: base.x - 19, y: base.y - 2, width: 38, height: 3), cornerRadius: 1.5), with: .color(Color(white: 0.6)))
            if sin(t * 12) > 0 { context.fill(Path(ellipseIn: CGRect(x: base.x - 3, y: base.y - 10, width: 6, height: 4)), with: .color(pink.opacity(0.6))) }
        }
    }

    @ViewBuilder func badge(t: Double) -> some View {
        switch model.mood {
        case .sleeping:
            Image(systemName: "zzz").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.8))
                .offset(y: -6 * abs(sin(t * 0.8))).opacity(0.5 + 0.5 * abs(sin(t * 0.8)))
        case .listening:
            Image(systemName: "ear.fill").font(.system(size: 15)).foregroundColor(.white).opacity(0.6 + 0.4 * sin(t * 5))
        case .working:
            Image(systemName: "gearshape.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.8))
                .rotationEffect(.degrees(t * 120))
        case .speaking:
            Image(systemName: "waveform").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
        case .idle, .waving:
            EmptyView()
        }
    }
}

// MARK: - Natural voice (Kokoro, offline)

/// Runs ~/Lotus/voice/speak.py (installed by voice/setup.sh) as a helper that turns text into
/// natural speech on this Mac. If it isn't installed, Lotus uses the system voice instead.
final class NeuralVoice: NSObject, AVAudioPlayerDelegate {
    private let dir = home.appendingPathComponent("Lotus/voice")
    private var input: FileHandle?
    private var buffer = ""
    private var waiting: [((URL?) -> Void)?] = []  // one entry per request sent, in order; nil = cancelled
    private var player: AVAudioPlayer?
    private var finished: (() -> Void)?
    private(set) var ready = false

    func start() {
        let python = dir.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }
        let proc = Process()
        proc.executableURL = python
        proc.arguments = ["-I", dir.appendingPathComponent("speak.py").path]
        let toVoice = Pipe(), fromVoice = Pipe()
        proc.standardInput = toVoice
        proc.standardOutput = fromVoice
        proc.standardError = FileHandle.nullDevice
        fromVoice.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            DispatchQueue.main.async { self?.received(chunk) }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ready = false
                self.waiting.forEach { $0?(nil) }
                self.waiting = []
            }
        }
        guard (try? proc.run()) != nil else { return }
        input = toVoice.fileHandleForWriting
    }

    private func received(_ chunk: String) {
        buffer += chunk
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            if line == "ready" { ready = true; continue }
            guard !waiting.isEmpty else { continue }
            waiting.removeFirst()?(line.hasPrefix("/") ? URL(fileURLWithPath: line) : nil)
        }
    }

    /// Speaks `text`, then calls `done(true)`; calls `done(false)` instead if it can't, so the caller can fall back.
    func speak(_ text: String, voice: String, started: @escaping () -> Void, done: @escaping (Bool) -> Void) {
        guard ready, let input,
              let json = try? JSONSerialization.data(withJSONObject: ["text": text, "voice": voice, "speed": 1.05]) else { return done(false) }
        waiting.append { [weak self] url in
            guard let self, let url, let player = try? AVAudioPlayer(contentsOf: url) else { return done(false) }
            self.player = player
            self.finished = { done(true) }
            player.delegate = self
            started()
            player.play()
        }
        input.write(json + Data("\n".utf8))
    }

    /// Stops playback and drops anything still being prepared. No completion is called.
    func stop() {
        player?.stop()
        player = nil
        finished = nil
        waiting = waiting.map { _ in nil }
    }

    var isBusy: Bool { player?.isPlaying == true || waiting.contains { $0 != nil } }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let done = finished
        finished = nil
        done?()
    }
}

// MARK: - Chat window

struct ChatView: View {
    @ObservedObject var model: Model
    var send: (String, [URL]) -> Void
    var stop: () -> Void
    @State private var draft = ""
    @State private var files: [URL] = []
    @State private var dropping = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if model.messages.isEmpty {
                            Text("Type to Lotus, or drop a photo or file here and ask about it.\nYou can still just say “Hey Buddy”.")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 40)
                        }
                        ForEach(model.messages) { message in row(message).id(message.id) }
                        if model.mood == .working {
                            HStack { ProgressView().controlSize(.small); Text("Working on it…").foregroundStyle(.secondary)
                                Button("Stop", action: stop).buttonStyle(.link) }.id("working")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            if !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent).lineLimit(1)
                                Button { files.removeAll { $0 == file } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).accessibilityLabel("Remove \(file.lastPathComponent)")
                            }
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }.padding(.horizontal, 10).padding(.top, 8)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: pickFiles) { Image(systemName: "plus.circle").font(.title3) }
                    .buttonStyle(.plain).help("Attach photos or files").accessibilityLabel("Attach files")
                TextField("Message Lotus", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Send", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty && files.isEmpty)
            }
            .padding(10)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { if !files.contains(url) { files.append(url) } } }
                }
            }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .foregroundStyle(Color.accentColor).padding(6)
                    .overlay(Text("Drop to attach").font(.headline))
            }
        }
    }

    func row(_ message: ChatMessage) -> some View {
        HStack {
            if message.fromUser { Spacer(minLength: 40) }
            VStack(alignment: message.fromUser ? .trailing : .leading, spacing: 4) {
                ForEach(message.files, id: \.self) { file in
                    Label(file.lastPathComponent, systemImage: "paperclip").font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(message.fromUser ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
            }
            if !message.fromUser { Spacer(minLength: 40) }
        }
    }

    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !files.isEmpty else { return }
        send(text.isEmpty ? "Look at what I've attached." : text, files)
        draft = ""
        files = []
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { files += panel.urls.filter { !files.contains($0) } }
    }
}

// MARK: - History, connections, instructions

/// Past conversations, month by month, from ~/Lotus/Conversations.
struct HistoryView: View {
    @State private var months: [URL] = []
    @State private var selected: URL?
    @State private var text = ""

    var body: some View {
        HSplitView {
            List(months, id: \.self, selection: $selected) { url in
                Text(title(url))
            }
            .frame(minWidth: 140, maxWidth: 200)
            ScrollView {
                Text(attributed(text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .onAppear(perform: load)
        .onChange(of: selected) { _, url in text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }
        .overlay { if months.isEmpty { Text("No conversations yet.").foregroundStyle(.secondary) } }
    }

    func load() {
        months = ((try? FileManager.default.contentsOfDirectory(at: Transcript.folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        if selected == nil { selected = months.first }
    }

    func title(_ url: URL) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: url.deletingPathExtension().lastPathComponent) else { return url.lastPathComponent }
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }
}

/// What Lotus is connected to: Claude sign-in, built-ins, Claude Code connectors and plugins, GitHub.
struct ConnectionsView: View {
    struct Item: Identifiable { let id = UUID(); let name: String; let status: String; let ok: Bool? }
    @State private var connectors: [Item] = []
    @State private var plugins: [Item] = []
    @State private var signedIn: Bool?
    @State private var loading = false
    @AppStorage("useConnectors") private var useConnectors = false

    var body: some View {
        Form {
            Section("Account") {
                row("Claude", signedIn == nil ? "Checking…" : signedIn! ? "Signed in" : "Not signed in (menu bar › Sign in)", signedIn)
            }
            Section("Built in") {
                row("Websites in your Chrome", "LinkedIn, Gmail, Instagram… through the Claude in Chrome extension", true)
                row("Apple Calendar, Reminders, Mail, Music", "Through AppleScript, on this Mac", true)
                row("Files, screen, clicks, voice", "On this Mac", true)
                row("GitHub", githubStatus, FileManager.default.isExecutableFile(atPath: githubPath ?? "") ? true : nil)
            }
            Section {
                Toggle("Load every connector on every request (slower)", isOn: $useConnectors)
                Text("Off: Lotus loads a connector only when you name it, like “search Scite for…”.").font(.caption).foregroundStyle(.secondary)
                if loading { HStack { ProgressView().controlSize(.small); Text("Checking connectors…") } }
                ForEach(connectors) { row($0.name, $0.status, $0.ok) }
                Button("Connect or sign in to connectors…") {
                    if let claude = Agent.claudePath { runInTerminal(claude, "") }  // then type /mcp
                }
                Text("Opens Claude Code in Terminal; type /mcp there to sign in to a connector.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Claude Code connectors") }
            Section("Plugins") {
                ForEach(plugins) { row($0.name, $0.status, $0.ok) }
            }
        }
        .formStyle(.grouped)
        .toolbar { Button("Refresh", action: refresh) }
        .onAppear { if connectors.isEmpty { refresh() } }
    }

    var githubPath: String? { [home.path + "/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    var githubStatus: String { githubPath == nil ? "Not set up: ask Lotus to install the GitHub CLI, then run gh auth login" : "GitHub CLI installed" }

    func row(_ name: String, _ status: String, _ ok: Bool?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok == true ? .green : ok == false ? .red : .orange)
            VStack(alignment: .leading) {
                Text(name)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func refresh() {
        loading = true
        DispatchQueue.global().async {
            let signed = isSignedIn()
            let mcp = runClaude(["mcp", "list"])
            let plug = runClaude(["plugin", "list"])
            let parsedConnectors: [Item] = mcp.split(separator: "\n").compactMap { line in
                guard let colon = line.firstIndex(of: ":"), line.contains(" - ") else { return nil }
                let rawName = String(line[..<colon]) == "plugin" ? line.split(separator: ":").dropFirst().prefix(2).joined(separator: ":") : String(line[..<colon])
                let status = String(line.components(separatedBy: " - ").last ?? "").trimmingCharacters(in: .whitespaces)
                let ok: Bool? = status.contains("✔") ? true : status.contains("✘") ? false : nil
                return Item(name: rawName, status: status.replacingOccurrences(of: "✔ ", with: "").replacingOccurrences(of: "✘ ", with: "")
                    .replacingOccurrences(of: "! ", with: ""), ok: ok)
            }
            var parsedPlugins: [Item] = []
            var name: String?
            for line in plug.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if line.hasPrefix("❯ ") { name = String(line.dropFirst(2)) }
                else if line.hasPrefix("Status:"), let n = name {
                    parsedPlugins.append(Item(name: n, status: String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces), ok: line.contains("✔")))
                    name = nil
                }
            }
            DispatchQueue.main.async {
                signedIn = signed
                connectors = parsedConnectors
                plugins = parsedPlugins
                loading = false
            }
        }
    }

    func runClaude(_ args: [String]) -> String {
        guard let claude = Agent.claudePath else { return "" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = args
        proc.currentDirectoryURL = home
        proc.environment = Agent.environment(for: claude)
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = out
        proc.standardInput = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// The user's standing instructions for Lotus, saved to ~/Lotus/instructions.md.
struct InstructionsView: View {
    @State private var text = ""
    @State private var saved = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tell Lotus how to work for you. It follows these in every conversation. Keep them short; spoken replies stay brief either way.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .border(Color.secondary.opacity(0.3))
                .onChange(of: text) { _, _ in saved = false }
            HStack {
                Text(saved ? "Saved" : "Not saved").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    try? FileManager.default.createDirectory(at: Agent.instructions.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? text.write(to: Agent.instructions, atomically: true, encoding: .utf8)
                    saved = true
                }
                .keyboardShortcut("s")
            }
        }
        .padding(14)
        .onAppear {
            text = (try? String(contentsOf: Agent.instructions, encoding: .utf8)) ?? ""
            DispatchQueue.main.async { saved = true }
        }
    }
}

/// A small lotus for the menu bar (a template image, so it follows light and dark mode).
func lotusMenuIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
        let base = NSPoint(x: 10, y: 3)
        for (length, width, angle) in [(9.0, 4.5, -62.0), (9.0, 4.5, 62.0), (12.0, 5.0, -28.0), (12.0, 5.0, 28.0), (14.0, 5.5, 0.0)] {
            let p = NSBezierPath()
            p.move(to: .zero)
            p.curve(to: NSPoint(x: 0, y: length), controlPoint1: NSPoint(x: -width, y: length * 0.3), controlPoint2: NSPoint(x: -width * 0.45, y: length * 0.86))
            p.curve(to: .zero, controlPoint1: NSPoint(x: width * 0.45, y: length * 0.86), controlPoint2: NSPoint(x: width, y: length * 0.3))
            var t = AffineTransform(translationByX: base.x, byY: base.y)
            t.rotate(byDegrees: -angle)
            p.transform(using: t)
            NSColor.black.setStroke()
            p.lineWidth = 1.2
            p.stroke()
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Lotus"
    return image
}

// MARK: - Ears, brain, voice

final class Companion: NSObject, AVSpeechSynthesizerDelegate {
    let model = Model()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: defaults.string(forKey: "locale") ?? "en-US"))
    private let audio = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    let neural = NeuralVoice()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0  // ignores callbacks from recognition tasks we already stopped
    private var silence: Timer?
    private var clearBubble: Timer?
    private var busy = false
    private var awake = false  // tapped: treat the next thing said as a request, no wake word needed
    var muted = false
    var sessionID: String? {
        get {
            guard let id = defaults.string(forKey: "sessionID") else { return nil }
            // Resuming reloads the whole conversation each time, so a long session makes every reply slower.
            // Past ~500 KB, start fresh; the memory file keeps what matters.
            let file = Housekeeping.sessions.appendingPathComponent("\(id).jsonl")
            if ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0) > 500_000 {
                defaults.removeObject(forKey: "sessionID")
                return nil
            }
            return id
        }
        set { defaults.set(newValue, forKey: "sessionID") }
    }

    /// "cute" (higher, female voice) or "deep" (lower, male voice).
    var voiceStyle: String {
        get { defaults.string(forKey: "voiceStyle") ?? "cute" }
        set { defaults.set(newValue, forKey: "voiceStyle") }
    }

    /// The best installed voice for the style and language (Premium > Enhanced > Default).
    private var voice: AVSpeechSynthesisVoice? {
        if let id = defaults.string(forKey: "voice") { return AVSpeechSynthesisVoice(identifier: id) }
        let lang = (defaults.string(forKey: "locale") ?? "en-US").replacingOccurrences(of: "_", with: "-")
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(lang.prefix(2))) }
        let gendered = all.filter { $0.gender == (voiceStyle == "deep" ? .male : .female) }
        let pool = gendered.isEmpty ? all : gendered
        return pool.max { ($0.quality.rawValue, $0.language == lang ? 1 : 0) < ($1.quality.rawValue, $1.language == lang ? 1 : 0) }
    }

    override init() {
        super.init()
        synth.delegate = self
        neural.start()
    }

    func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    if status == .authorized && mic { self.startListening() }
                    else { self.show("I need Microphone and Speech Recognition access (System Settings › Privacy & Security). You can still type to me from the menu bar.") }
                }
            }
        }
    }

    func show(_ text: String, for seconds: Double? = nil) {
        clearBubble?.invalidate()
        model.bubble = text
        if let seconds {
            clearBubble = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.model.bubble = "" }
        }
    }

    func startListening() {
        guard !busy, !muted, task == nil, let recognizer, recognizer.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Privacy: keep speech recognition on this Mac. Never send audio to Apple's servers.
        guard recognizer.supportsOnDeviceRecognition else {
            show("On-device speech isn't available for this language. Download it in System Settings › Keyboard › Dictation, or type to me.")
            return
        }
        req.requiresOnDeviceRecognition = true
        request = req

        let input = audio.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
        audio.prepare()
        do { try audio.start() } catch { show("Microphone error: \(error.localizedDescription)"); return }

        generation += 1
        let gen = generation
        model.mood = awake ? .listening : .idle
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.heard(result, error)
            }
        }
    }

    func stopListening() {
        generation += 1
        silence?.invalidate()
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    /// Tap on the character: listen now, no wake word needed.
    func wake() {
        if busy { return stop() }
        guard !muted else { show("I'm muted. Unmute me from the menu bar.", for: 4); return }
        stopListening()
        awake = true
        show("I'm listening…")
        startListening()
        armSilence("", wait: 6)
    }

    private func heard(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        if let text = result?.bestTranscription.formattedString,
           let cmd = awake ? (command(after: text) ?? clean(text.lowercased())) : command(after: text) {
            awake = true
            model.mood = .listening
            show(cmd.isEmpty ? "I'm listening…" : cmd)
            // Wait for a pause in speech before acting; allow longer after a bare "Hey Claude".
            // Wait until you've really finished: a short start is often a thinking pause, so wait longer.
            let pause = defaults.object(forKey: "pauseSeconds") as? Double ?? 1.8
            let words = cmd.split(separator: " ").count
            armSilence(cmd, wait: words == 0 ? 6 : words < 4 ? pause + 1 : pause)
        }
        // Recognition tasks end on their own after a while; start a fresh one.
        if error != nil || result?.isFinal == true {
            stopListening()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.startListening() }
        }
    }

    private func armSilence(_ cmd: String, wait: Double) {
        silence?.invalidate()
        silence = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stopListening()
            self.awake = false
            if cmd.isEmpty { self.lastSaid = nil; self.startListening() } else { self.ask(cmd) }
        }
    }

    /// Tap while it's working or talking: drop everything and go back to listening.
    func stop() {
        askID += 1  // ignore the reply of the request we're cancelling
        Agent.current?.terminate()
        Agent.current = nil
        if synth.isSpeaking { quiet = true; synth.stopSpeaking(at: .immediate) }
        neural.stop()
        busy = false
        awake = false
        show("Okay, stopped.", for: 3)
        startListening()
    }

    private var askID = 0
    private var quiet = false

    /// `spoken: false` for typed chat: the reply shows in the chat window without being read aloud.
    func ask(_ text: String, forceScreen: Bool = false, files: [URL] = [], spoken: Bool = true) {
        stopListening()
        model.messages.append(ChatMessage(fromUser: true, text: text, files: files))
        askID += 1
        let id = askID
        busy = true
        awake = false
        model.mood = .working
        let screen = forceScreen || wantsScreen(text)
        if screen && !CGPreflightScreenCaptureAccess() {
            // Without Screen Recording, macOS hands back a blank picture; say so instead of guessing.
            Permissions.open(.screen)  // stays busy while speaking so it doesn't hear itself
            return say("I can't see your screen yet. Switch Lotus on in Screen Recording, the page I just opened, then choose Quit and Reopen.")
        }
        show("“\(text)”\n\(screen ? "Looking at your screen…" : "On it…")")
        var request = lastSaid.map { "(You just said to me: \"\($0)\") \(text)" } ?? text
        lastSaid = nil
        if !spoken {
            request += "\n\n(Typed in the chat window, not spoken: reply in full, Markdown is fine.)"
        }
        if !files.isEmpty {
            request += "\n\n(I've attached these files. Read them: " + files.map(\.path).joined(separator: ", ") + ")"
        }
        Agent.run(request, session: sessionID, withScreen: screen) { [weak self] reply, session in
            guard let self, id == self.askID else { return }
            Agent.current = nil
            if let session { self.sessionID = session }
            Transcript.add(you: text + (files.isEmpty ? "" : " [attached: " + files.map(\.lastPathComponent).joined(separator: ", ") + "]"), lotus: reply)
            self.model.messages.append(ChatMessage(fromUser: false, text: reply))
            if spoken { self.say(reply) } else { self.finishQuietly() }
        }
    }

    private func finishQuietly() {
        busy = false
        model.mood = .idle
        model.bubble = ""
        startListening()
    }

    /// Says something on its own (a hello or a nudge), then listens a few seconds for a reply.
    func chat(_ line: String) {
        guard !busy, !muted else { model.mood = .idle; return }
        stopListening()
        busy = true
        lastSaid = line
        say(line)
    }

    /// What Lotus said unprompted, so a quick "yes" or "sure" in reply has context. Cleared when unanswered.
    private var lastSaid: String?

    private func say(_ text: String) {
        let spoken = ["**", "*", "#", "`"].reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
        let kokoro = defaults.string(forKey: "kokoroVoice") ?? (voiceStyle == "deep" ? "am_michael" : "af_heart")
        // Words appear the moment the voice starts, not before.
        let begin = { [weak self] in self?.model.mood = .speaking; self?.show(text) }
        neural.speak(spoken, voice: kokoro, started: begin) { [weak self] ok in
            if ok { self?.doneSpeaking() } else { begin(); self?.systemSpeak(spoken) }
        }
    }

    private func systemSpeak(_ spoken: String) {
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        utterance.pitchMultiplier = voiceStyle == "deep" ? 0.95 : 1.05  // small shifts only; big ones sound robotic
        synth.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { doneSpeaking() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { doneSpeaking() }

    private func doneSpeaking() {
        DispatchQueue.main.async {
            if self.quiet { self.quiet = false; return }  // stopped by a tap; stop() already reset things
            self.busy = false
            self.show(self.model.bubble, for: 8)
            // Keep the conversation going: for a few seconds, reply without saying "Hey Buddy" again.
            guard !self.muted else { return }
            self.awake = true
            self.startListening()
            self.armSilence("", wait: 7)
        }
    }

    func shutUp() { if busy { stop() } }
}

// MARK: - Phone access (Claude Code Remote Control)

final class PhoneAccess {
    private var remote: Process?
    private var awake: Process?
    var onChange: (String) -> Void = { _ in }
    var isOn: Bool { remote != nil }

    /// Runs `claude remote-control` in the background so the Claude phone app can reach this Mac,
    /// and keeps the Mac from idle-sleeping while it runs.
    func start() {
        stop()
        guard let claude = Agent.claudePath else { return onChange("Claude Code isn't installed.") }
        let log = home.appendingPathComponent("Library/Logs/Lotus-phone.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["remote-control", "--name", "Lotus"]
        proc.currentDirectoryURL = home
        proc.environment = Agent.environment(for: claude)
        proc.standardOutput = try? FileHandle(forWritingTo: log)
        proc.standardError = proc.standardOutput
        proc.standardInput = FileHandle.nullDevice
        let started = Date()
        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self, self.remote === p else { return }
                self.stop()
                // Exiting straight away usually means first-time setup needs a real terminal.
                if Date().timeIntervalSince(started) < 20 { self.openInTerminal(claude) }
                else { self.onChange("Phone access stopped. Turn it on again from the menu bar.") }
            }
        }
        do { try proc.run() } catch { return onChange("Couldn't start phone access: \(error.localizedDescription)") }
        remote = proc

        let caffeinate = Process()
        caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        caffeinate.arguments = ["-i", "-w", String(proc.processIdentifier)]  // exits when remote-control does
        try? caffeinate.run()
        awake = caffeinate
        onChange("Phone access is on. Open the Claude app on your phone and pick the “Lotus” session.")
    }

    func stop() {
        let proc = remote
        remote = nil
        proc?.terminate()
        awake?.terminate()
        awake = nil
    }

    private func openInTerminal(_ claude: String) {
        onChange("Phone access needs a one-time setup. Finish it in the Terminal window.")
        runInTerminal(claude, "remote-control --name Lotus")
    }
}

/// Opens Terminal running claude with `arguments`, for steps that need you (sign-in, first-time setup).
func runInTerminal(_ program: String, _ arguments: String) {
    let quoted = "'" + program.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let command = "cd ~ && \(quoted) \(arguments)"
        .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(command)\"\nend tell")?.executeAndReturnError(nil)
}

/// Claude Code keeps its sign-in in your Keychain and refreshes it itself, so this is a one-time step.
func isSignedIn() -> Bool {
    guard let claude = Agent.claudePath else { return false }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: claude)
    proc.arguments = ["auth", "status"]
    proc.environment = Agent.environment(for: claude)
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    proc.standardInput = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return false }
    proc.waitUntilExit()
    return proc.terminationStatus == 0
}

// MARK: - Permissions

enum Permissions {
    enum Kind: CaseIterable {
        case microphone, speech, screen, accessibility
        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .speech: "Speech Recognition"
            case .screen: "Screen Recording"
            case .accessibility: "Accessibility (clicking for you)"
            }
        }
        var granted: Bool {
            switch self {
            case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            case .speech: SFSpeechRecognizer.authorizationStatus() == .authorized
            case .screen: CGPreflightScreenCaptureAccess()
            case .accessibility: AXIsProcessTrusted()
            }
        }
        var pane: String {
            switch self {
            case .microphone: "Privacy_Microphone"
            case .speech: "Privacy_SpeechRecognition"
            case .screen: "Privacy_ScreenCapture"
            case .accessibility: "Privacy_Accessibility"
            }
        }
    }

    static func open(_ kind: Kind) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.pane)")!)
    }
}

// MARK: - Conversation log

/// Every exchange, as plain text you can read any time: ~/Lotus/Conversations/2026-11.md, one file per month.
enum Transcript {
    static let folder = home.appendingPathComponent("Lotus/Conversations")

    static func add(you: String, lotus: String, at date: Date = Date(), in folder: URL = folder) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let month = DateFormatter(), time = DateFormatter()
        month.dateFormat = "yyyy-MM"
        time.dateFormat = "EEE d MMM, HH:mm"
        let file = folder.appendingPathComponent("\(month.string(from: date)).md")
        let entry = "**\(time.string(from: date)) · You:** \(you)\n\n**Lotus:** \(lotus)\n\n---\n\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? ("# Conversations with Lotus, \(month.string(from: date))\n\n" + entry).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Text is tiny (about 10 MB a year with heavy use), but cap it anyway: past 100 MB the oldest months go.
    static func trim(limit: Int = 100_000_000, in folder: URL = folder) {
        let fm = FileManager.default
        var files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        while total > limit, files.count > 1 {
            let oldest = files.removeFirst()
            total -= (try? oldest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? fm.removeItem(at: oldest)
        }
    }
}

// MARK: - Housekeeping

/// Keeps Lotus small on disk: conversation logs older than two weeks go, stray screenshots go,
/// and the memory file gets tidied when it grows.
enum Housekeeping {
    /// Where Claude Code keeps Lotus's conversations (it names the folder after Lotus's working directory).
    static let sessions = home.appendingPathComponent(".claude/projects/" +
        Agent.memory.deletingLastPathComponent().path.replacingOccurrences(of: "/", with: "-"))

    static func run() {
        Transcript.trim()
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        for url in (try? fm.contentsOfDirectory(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let changed = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, changed < cutoff {
                try? fm.removeItem(at: url)
            }
        }
        if let id = defaults.string(forKey: "sessionID"), !fm.fileExists(atPath: sessions.appendingPathComponent("\(id).jsonl").path) {
            defaults.removeObject(forKey: "sessionID")  // that conversation was cleaned up; start fresh
        }
        try? fm.removeItem(at: Agent.cache)
        let size = (try? fm.attributesOfItem(atPath: Agent.memory.path)[.size] as? Int) ?? 0
        if size > 8_000 {
            Agent.run("Housekeeping, no reply needed: tidy your memory file \(Agent.memory.path) so it is under 5 KB. " +
                      "Merge duplicates and drop outdated lines, keep every idea and goal, keep the section headings.",
                      session: nil, withScreen: false) { _, _ in }
        }
    }
}

// MARK: - App shell

final class AppDelegate: NSObject, NSApplicationDelegate {
    let companion = Companion()
    let phone = PhoneAccess()
    var panel: NSPanel!
    var status: NSStatusItem!
    var dragOffset: NSPoint?
    var signedIn = true

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false  // stay on screen while you use other apps
        Agent.ensureMemory()
        panel.contentView = NSHostingView(rootView: Buddy(model: companion.model,
                                                          look: { [weak self] in self?.gaze() ?? .zero },
                                                          onTap: { [weak self] in self?.companion.wake() },
                                                          onDrag: { [weak self] dragging in self?.drag(dragging) }))
        panel.setFrameOrigin(savedOrigin())
        panel.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = lotusMenuIcon()
        phone.onChange = { [weak self] text in self?.companion.show(text, for: 10); self?.buildMenu() }
        buildMenu()

        companion.requestPermissionsAndStart()
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)  // lets Claude click for you
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }  // adds Lotus to Screen Recording
        // One line per launch so permission problems can be diagnosed: ~/Library/Logs/Lotus.log
        let status = Permissions.Kind.allCases.map { "\($0.title)=\($0.granted ? "yes" : "no")" }.joined(separator: " ")
        let line = "\(Date()) \(status)\n"
        let log = home.appendingPathComponent("Library/Logs/Lotus.log")
        if ((try? FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int) ?? 0) > 50_000 { try? FileManager.default.removeItem(at: log) }
        if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(to: log, atomically: true, encoding: .utf8) }
        if defaults.bool(forKey: "phoneAccess") { phone.start() }
        refreshSignIn()
        Housekeeping.run()
        // First run: start Lotus at login so it's always there (turn off in the menu).
        if !defaults.bool(forKey: "loginItemSet") {
            defaults.set(true, forKey: "loginItemSet")
            try? SMAppService.mainApp.register()
            buildMenu()
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.idleTick() }
        NSApp.mainMenu = mainMenu()
        // Opened by you (not at login): show the window straight away.
        let atLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue ?? false
        if !atLogin { openChat() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.wave("Hi! I'm Lotus. Say “Hey Buddy” whenever you need me.", speak: false) }
    }

    // MARK: Personality while you're not chatting

    let greetings = ["Welcome back! I missed you.", "Oh hi! You're back.", "Hey there! Ready when you are."]
    let nudges = ["Hi! I'm still here if you need me.", "Want to learn something new about biotech today?",
                  "Stuck on anything? I can look at your screen.", "Remember to drink some water!",
                  "You're doing great. Need a hand?", "Got an idea? Tell me and I'll remember it.",
                  "How about a quick stretch break?"]
    var lastNudge = Date()
    var wasAway = false

    /// Where the cursor is relative to Lotus, so its eyes can follow you.
    func gaze() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let center = NSPoint(x: panel.frame.maxX - 60, y: panel.frame.minY + 40)
        return CGPoint(x: max(-1, min(1, (mouse.x - center.x) / 300)), y: max(-1, min(1, (mouse.y - center.y) / 300)))
    }

    /// Sleeps when you've been away 5 minutes, greets you when you're back, and waves now and then.
    func idleTick() {
        let model = companion.model
        guard model.resting else { lastNudge = Date(); return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idleSeconds > 300 {
            if model.mood != .sleeping { model.mood = .sleeping; model.bubble = "" }
            wasAway = true
            return
        }
        if wasAway {
            wasAway = false
            let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            if defaults.double(forKey: "lastBriefing") < today {
                defaults.set(today, forKey: "lastBriefing")
                let hour = Calendar.current.component(.hour, from: Date())
                let hello = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
                return wave("\(hello)! Want me to run through today's schedule and reminders?", speak: true)
            }
            return wave(greetings.randomElement()!, speak: true)
        }
        if model.mood == .sleeping { model.mood = .idle }
        let every = defaults.object(forKey: "nudgeMinutes") as? Double ?? 45
        if Date().timeIntervalSince(lastNudge) > every * 60 { wave(nudges.randomElement()!, speak: true) }
    }

    func wave(_ line: String, speak: Bool) {
        lastNudge = Date()
        companion.model.mood = .waving
        companion.show(line, for: 7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard self.companion.model.mood == .waving else { return }
            if speak && defaults.object(forKey: "chatty") as? Bool ?? true { self.companion.chat(line) }
            else { self.companion.model.mood = .idle }
        }
    }

    @objc func toggleChatty() {
        defaults.set(!(defaults.object(forKey: "chatty") as? Bool ?? true), forKey: "chatty")
        buildMenu()
    }

    @objc func toggleNoLimits() {
        let on = defaults.string(forKey: "permissionMode") == "bypassPermissions"
        defaults.set(on ? "auto" : "bypassPermissions", forKey: "permissionMode")
        companion.show(on ? "Back to safe hands-free mode." : "No limits: I'll act without any safety check (privacy blocks still apply).", for: 6)
        buildMenu()
    }

    /// Runs the bundled voice installer in Terminal (about 340 MB, downloaded once). Restart Lotus afterwards.
    @objc func installVoice() {
        guard let script = Bundle.main.path(forResource: "extras", ofType: "sh") else { return }
        runInTerminal("/bin/bash", "'\(script)'")
        companion.show("Installing my voice and tools in Terminal. Restart me when it says it's done.", for: 10)
    }

    @objc func openConversations() {
        try? FileManager.default.createDirectory(at: Transcript.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Transcript.folder)
    }

    @objc func openMemory() { NSWorkspace.shared.open(Agent.memory) }

    /// Shows which macOS permissions Lotus has and opens the page for the first one missing.
    @objc func checkPermissions() {
        let missing = Permissions.Kind.allCases.filter { !$0.granted }
        let alert = NSAlert()
        alert.messageText = missing.isEmpty ? "Lotus has every permission it needs." : "Lotus is missing some permissions"
        alert.informativeText = Permissions.Kind.allCases.map { "\($0.granted ? "✅" : "❌")  \($0.title)" }.joined(separator: "\n") +
            (missing.isEmpty ? "" : "\n\nmacOS only lets you switch these on yourself. After Screen Recording, choose Quit & Reopen.")
        alert.addButton(withTitle: missing.isEmpty ? "OK" : "Open \(missing[0].title) Settings")
        if !missing.isEmpty { alert.addButton(withTitle: "Later") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let first = missing.first { Permissions.open(first) }
    }

    /// Wipes Lotus and everything it stored or was allowed, after one confirmation.
    @objc func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Remove Lotus completely?"
        alert.informativeText = "This deletes the app, everything Lotus remembers, its voice, conversation history, settings and " +
            "signing certificate, and removes every permission you gave it. It can't be undone. Your Claude sign-in is kept."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Remove Everything")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let script = Bundle.main.path(forResource: "uninstall", ofType: "sh") else { return }
        phone.stop()
        try? SMAppService.mainApp.unregister()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script]
        try? proc.run()  // the script quits Lotus and deletes the app; it keeps running after we exit
    }

    func refreshSignIn() {
        DispatchQueue.global().async {
            let ok = isSignedIn()
            DispatchQueue.main.async {
                self.signedIn = ok
                if !ok { self.companion.show("Hi! Sign me in once: menu bar lotus › Sign in to Claude…", for: 15) }
                self.buildMenu()
            }
        }
    }

    @objc func signIn() {
        guard let claude = Agent.claudePath else { return companion.show("Claude Code isn't installed.", for: 6) }
        runInTerminal(claude, "auth login")
        companion.show("Approve the sign-in in your browser. You only do this once.", for: 10)
        // Check again once the browser step is likely done.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { self.refreshSignIn() }
    }

    @objc func signOut() {
        guard let claude = Agent.claudePath else { return }
        let alert = NSAlert()
        alert.messageText = "Sign Lotus out of Claude?"
        alert.informativeText = "Lotus won't be able to do anything until you sign in again."
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["auth", "logout"]
        proc.environment = Agent.environment(for: claude)
        try? proc.run()
        proc.waitUntilExit()
        companion.sessionID = nil
        refreshSignIn()
    }

    @objc func voiceCute() { companion.voiceStyle = "cute"; buildMenu() }
    @objc func voiceDeep() { companion.voiceStyle = "deep"; buildMenu() }

    /// Quitting Lotus stops everything it started: the running request, phone access and the voice helper
    /// (which exits on its own when Lotus goes away).
    func applicationWillTerminate(_ note: Notification) {
        phone.stop()
        Agent.current?.terminate()
    }

    /// Clicking Lotus's icon (Dock, Spotlight, Launchpad, Finder) while it's running: show up and listen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        openChat()
        return false
    }

    var chatWindow: NSWindow?

    /// The standard app menus, so Quit, Hide, copy/paste and window shortcuts work.
    func mainMenu() -> NSMenu {
        let bar = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            holder.submenu = menu
            bar.addItem(holder)
        }
        func entry(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        submenu("Lotus", [
            entry("About Lotus", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            entry("Open Chat", #selector(openChat), "o", target: self),
            .separator(),
            entry("Hide Lotus", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            entry("Quit Lotus", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Edit", [
            entry("Undo", Selector(("undo:")), "z"), entry("Redo", Selector(("redo:")), "Z"), .separator(),
            entry("Cut", #selector(NSText.cut(_:)), "x"), entry("Copy", #selector(NSText.copy(_:)), "c"),
            entry("Paste", #selector(NSText.paste(_:)), "v"), entry("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Window", [
            entry("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            entry("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return bar
    }

    /// A simple chat window: type instead of talking, and drop photos or files in for Lotus to look at.
    @objc func openChat() {
        if chatWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Lotus"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 340, height: 360)
            window.contentView = NSHostingView(rootView: TabView {
                ChatView(model: companion.model,
                         send: { [weak self] text, files in self?.companion.ask(text, files: files, spoken: false) },
                         stop: { [weak self] in self?.companion.stop() })
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                HistoryView().tabItem { Label("History", systemImage: "clock") }
                ConnectionsView().tabItem { Label("Connections", systemImage: "point.3.connected.trianglepath.dotted") }
                InstructionsView().tabItem { Label("Instructions", systemImage: "text.badge.star") }
            }.padding(.top, 6))
            window.center()
            chatWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        chatWindow?.makeKeyAndOrderFront(nil)
    }

    /// Bottom-right corner unless you've dragged it somewhere else.
    func savedOrigin() -> NSPoint {
        if let x = defaults.object(forKey: "x") as? Double, let y = defaults.object(forKey: "y") as? Double,
           NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: x + 250, y: y + 50)) }) {
            return NSPoint(x: x, y: y)
        }
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: screen.maxX - panel.frame.width - 12, y: screen.minY + 12)
    }

    func drag(_ dragging: Bool) {
        let mouse = NSEvent.mouseLocation
        if dragging {
            let offset = dragOffset ?? NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            dragOffset = offset
            panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        } else {
            dragOffset = nil
            defaults.set(Double(panel.frame.minX), forKey: "x")
            defaults.set(Double(panel.frame.minY), forKey: "y")
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "", on: Bool? = nil) {
            let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            i.target = self
            if let on { i.state = on ? .on : .off }
        }
        item("Talk to Lotus", #selector(talk), "l")
        item("Open chat", #selector(openChat), "o")
        item("Look at my screen…", #selector(lookAtScreen), "s")
        item("Stop talking", #selector(stopTalking), ".")
        item("New conversation", #selector(newConversation), "n")
        menu.addItem(.separator())
        item("Voice: Cute", #selector(voiceCute), on: companion.voiceStyle == "cute")
        item("Voice: Deep", #selector(voiceDeep), on: companion.voiceStyle == "deep")
        item("Says hi now and then", #selector(toggleChatty), on: defaults.object(forKey: "chatty") as? Bool ?? true)
        item("Mute microphone", #selector(toggleMute), "m", on: companion.muted)
        item("No limits (skip safety checks)", #selector(toggleNoLimits), on: defaults.string(forKey: "permissionMode") == "bypassPermissions")
        item("What Lotus remembers…", #selector(openMemory))
        item("Conversation history…", #selector(openConversations))
        item("Check permissions…", #selector(checkPermissions))
        if !FileManager.default.fileExists(atPath: home.appendingPathComponent("Lotus/voice/kokoro-v1.0.onnx").path) {
            item("Install voice and extras…", #selector(installVoice))
        }
        item("Phone access", #selector(togglePhone), on: phone.isOn)
        item("Open at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        item("Move back to corner", #selector(resetPosition))
        menu.addItem(.separator())
        if signedIn { item("Sign out of Claude…", #selector(signOut)) } else { item("Sign in to Claude…", #selector(signIn)) }
        menu.addItem(.separator())
        item("Uninstall Lotus…", #selector(uninstall))
        menu.addItem(withTitle: "Quit Lotus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
    }

    @objc func talk() { companion.wake() }
    @objc func lookAtScreen() { prompt(title: "What should I look at on your screen?", screen: true) }

    func prompt(title: String, screen: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        if screen { alert.informativeText = "Lotus takes one screenshot, sends it with your question, then deletes it." }
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = screen ? "e.g. why won't this build?" : "e.g. find my latest PDF and summarise it"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.isEmpty && screen ? "Look at my screen and help me with what I'm stuck on." : field.stringValue
        if !text.isEmpty { companion.ask(text, forceScreen: screen) }
    }

    @objc func stopTalking() { companion.shutUp() }

    @objc func toggleMute() {
        companion.muted.toggle()
        if companion.muted { companion.stopListening(); companion.show("Muted. I can't hear anything now.", for: 4) }
        else { companion.show("Listening again.", for: 3); companion.startListening() }
        buildMenu()
    }

    @objc func togglePhone() {
        let on = !phone.isOn
        defaults.set(on, forKey: "phoneAccess")
        if on { phone.start() } else { phone.stop(); companion.show("Phone access is off.", for: 4) }
        buildMenu()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            companion.show("Couldn't change login item: \(error.localizedDescription). Move Lotus to Applications first.", for: 8)
        }
        buildMenu()
    }

    @objc func resetPosition() {
        defaults.removeObject(forKey: "x")
        defaults.removeObject(forKey: "y")
        panel.setFrameOrigin(savedOrigin())
    }

    @objc func newConversation() {
        companion.sessionID = nil
        companion.show("Fresh start! Say “Hey Buddy”, or tap me.", for: 5)
    }
}

if CommandLine.arguments.dropFirst().first == "--click" { Pointer.run(CommandLine.arguments) }
if CommandLine.arguments.contains("--selftest") {
    selfTest()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)  // a normal app: Dock icon with a running dot, app menu, Quit closes everything
app.run()
