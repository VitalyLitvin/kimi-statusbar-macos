import AppKit
import Foundation

// Kimi Status Bar — menu bar app for Kimi Code CLI.
// Reads ~/.kimi-code/statusbar/state.json (written by Kimi Code hooks) and
// sessions.d/ (one file per live session). Quits itself when no sessions remain.

struct StatusState {
    var state: String = "idle"   // idle | thinking | tool | permission | waiting | done
    var label: String = ""
    var tool: String = ""
    var project: String = ""
    var title: String = ""
    var sessionId: String = ""
    var startedAt: TimeInterval = 0  // seconds since 1970, 0 = not running
    var ts: TimeInterval = 0         // seconds since 1970, last hook event
}

final class StatusStore {
    private let dir: URL
    private let stateURL: URL
    private let sessionsURL: URL

    init() {
        // KIMI_STATUSBAR_DIR overrides the data dir (for KIMI_CODE_HOME setups
        // where hooks write elsewhere; export it via launchctl setenv).
        if let override = ProcessInfo.processInfo.environment["KIMI_STATUSBAR_DIR"], !override.isEmpty {
            dir = URL(fileURLWithPath: override)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            dir = home.appendingPathComponent(".kimi-code/statusbar")
        }
        stateURL = dir.appendingPathComponent("state.json")
        sessionsURL = dir.appendingPathComponent("sessions.d")
    }

    func read() -> StatusState {
        var s = StatusState()
        guard let data = try? Data(contentsOf: stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return s
        }
        s.state = obj["state"] as? String ?? "idle"
        s.label = obj["label"] as? String ?? ""
        s.tool = obj["tool"] as? String ?? ""
        s.project = obj["project"] as? String ?? ""
        s.title = obj["title"] as? String ?? ""
        s.sessionId = obj["sessionId"] as? String ?? ""
        s.startedAt = obj["startedAt"] as? TimeInterval ?? 0
        s.ts = obj["ts"] as? TimeInterval ?? 0

        // A "working" state whose last event is long gone means the session died
        // without SessionEnd (crash, killed terminal). Hooks fire on every tool
        // call, so a live working session never goes minutes without an update.
        let age = Date().timeIntervalSince1970 - s.ts
        if s.ts > 0 && age > 120 && (s.state == "thinking" || s.state == "tool") {
            s.state = "waiting"
            s.label = "Idle"
            s.startedAt = 0
        }
        // "Done" is a moment, not a status: once the user has had time to notice,
        // fall back to waiting-for-input.
        if s.state == "done" && age > 45 {
            s.state = "waiting"
            s.label = "Waiting for input"
        }
        return s
    }

    // A session file counts as live only if some hook touched it recently.
    // Sessions that died without SessionEnd (killed terminal, print-mode runs)
    // leave files behind; their mtime goes stale and the app can quit.
    // Any new hook event re-touches the file and relaunches the app (update.js).
    func liveSessionCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        let cutoff = Date().addingTimeInterval(-600)
        return files.filter { url in
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (mtime ?? .distantPast) > cutoff
        }.count
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var current = StatusState()
    private var sessions = 0

    // Self-quit: with no session files for this long, the app is no longer needed.
    private let idleQuitDelay: TimeInterval = 15
    private var emptySince: Date?

    private var completionSound: NSSound?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let path = Bundle.main.path(forResource: "completion", ofType: "mp3") {
            completionSound = NSSound(contentsOfFile: path, byReference: false)
        }

        configureStatusItem()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.font = NSFont.systemFont(ofSize: 14, weight: .regular)
    }

    private func refresh() {
        let previousState = current.state
        current = store.read()
        sessions = store.liveSessionCount()

        // Completion sound on a fresh transition into "done" (turn finished or a
        // background task completed). The ts guard keeps a relaunched app from
        // replaying the sound for a long-past completion.
        let now = Date().timeIntervalSince1970
        if previousState != "done" && current.state == "done" && now - current.ts < 15 {
            playCompletionSound()
        }

        if sessions == 0 {
            if emptySince == nil { emptySince = Date() }
            if let since = emptySince, Date().timeIntervalSince(since) > idleQuitDelay {
                NSApp.terminate(nil)
                return
            }
        } else {
            emptySince = nil
        }

        render()
        statusItem.menu = makeMenu()
    }

    private func render() {
        guard let button = statusItem.button else { return }

        let color: NSColor
        let title: String
        if sessions == 0 {
            color = .systemGray
            title = " Kimi"
        } else {
            switch current.state {
            case "thinking", "tool":
                color = NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)
            case "permission":
                color = .systemOrange
            case "done":
                color = NSColor(calibratedRed: 0.35, green: 0.8, blue: 0.45, alpha: 1.0)
            default: // waiting, idle
                color = NSColor(calibratedRed: 0.96, green: 0.75, blue: 0.25, alpha: 1.0)
            }
            var text = " " + (current.label.isEmpty ? current.state.capitalized : current.label)
            if current.startedAt > 0 {
                text += " " + formatDuration(Date().timeIntervalSince1970 - current.startedAt)
            }
            title = text
        }

        button.image = makeMoonIcon(color: color)
        button.title = title
        button.toolTip = sessions == 0
            ? "Kimi Code is not running"
            : "Kimi Code: \(current.label.isEmpty ? current.state : current.label)"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        if sessions > 0 {
            let statusText = current.label.isEmpty ? current.state.capitalized : current.label
            let status = NSMenuItem(title: "Kimi Code: \(statusText)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)

            if !current.project.isEmpty {
                let project = NSMenuItem(title: "Project: \(current.project)", action: nil, keyEquivalent: "")
                project.isEnabled = false
                menu.addItem(project)
            }
            if !current.title.isEmpty {
                let title = NSMenuItem(title: "Session: \(current.title)", action: nil, keyEquivalent: "")
                title.isEnabled = false
                menu.addItem(title)
            }
            if sessions > 1 {
                let multi = NSMenuItem(title: "\(sessions) sessions active", action: nil, keyEquivalent: "")
                multi.isEnabled = false
                menu.addItem(multi)
            }
        } else {
            let idle = NSMenuItem(title: "Kimi Code: not running", action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Kimi CLI", action: #selector(openKimiCLI), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Play Completion Sound", action: #selector(playCompletionSoundFromMenu), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kimi Status Bar", action: #selector(quit), keyEquivalent: "q"))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let about = NSMenuItem(title: "Kimi Status Bar v\(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        return menu
    }

    @objc private func openKimiCLI() {
        let script = """
        tell application "Terminal"
          activate
          do script "kimi"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func playCompletionSound() {
        if let sound = completionSound {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    @objc private func playCompletionSoundFromMenu() {
        playCompletionSound()
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(String(format: "%02d", secs))s" }
        return "\(secs)s"
    }

    // Crescent moon, drawn per state color (not a template image, so the color shows).
    // Vertical lune (cut offset horizontally only): symmetric about the horizontal
    // axis, so it sits centered next to the text without manual nudging.
    private func makeMoonIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let full = NSBezierPath(ovalIn: NSRect(x: 4, y: 2, width: 14, height: 14))
        color.setFill()
        full.fill()

        // Punch out an offset circle to leave a crescent.
        if let ctx = NSGraphicsContext.current {
            ctx.compositingOperation = .clear
        }
        let cut = NSBezierPath(ovalIn: NSRect(x: 9, y: 2, width: 14, height: 14))
        cut.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        image.unlockFocus()
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
