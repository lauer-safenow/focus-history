import Cocoa
import Foundation

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

let logFile = NSString("~/.focus-history.log").expandingTildeInPath
let maxLogSize = 10 * 1024 * 1024 // 10 MB
let args = CommandLine.arguments
let isDaemon = args.contains("--daemon")

// --status: check if the daemon is running
if args.contains("--status") {
    let result = Process()
    result.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    result.arguments = ["list", "com.user.focus-history"]
    let pipe = Pipe()
    result.standardOutput = pipe
    result.standardError = pipe
    try? result.run()
    result.waitUntilExit()
    if result.terminationStatus == 0 {
        print("focus-history daemon is running.")
    } else {
        print("focus-history daemon is not running.")
        print("Start it with: focus-history --install")
    }
    exit(0)
}

// --install: install and start the launchd service
if args.contains("--install") {
    let binaryPath = CommandLine.arguments[0].hasPrefix("/")
        ? CommandLine.arguments[0]
        : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0]
    let plistPath = NSString("~/Library/LaunchAgents/com.user.focus-history.plist").expandingTildeInPath
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.user.focus-history</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(binaryPath)</string>
            <string>--daemon</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>/tmp/focus-history.out</string>
        <key>StandardErrorPath</key>
        <string>/tmp/focus-history.err</string>
    </dict>
    </plist>
    """
    do {
        // Unload first if already loaded
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", plistPath]
        try? unload.run()
        unload.waitUntilExit()

        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["load", plistPath]
        try load.run()
        load.waitUntilExit()
        print("Installed and started focus-history daemon.")
        print("It will start automatically on login.")
        print("Log file: \(logFile)")
        print("Query with: focus-history --history")
    } catch {
        print("Error installing: \(error)")
    }
    exit(0)
}

// --uninstall: stop and remove the launchd service
if args.contains("--uninstall") {
    let plistPath = NSString("~/Library/LaunchAgents/com.user.focus-history.plist").expandingTildeInPath
    let unload = Process()
    unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unload.arguments = ["unload", plistPath]
    try? unload.run()
    unload.waitUntilExit()
    try? FileManager.default.removeItem(atPath: plistPath)
    print("Uninstalled focus-history daemon.")
    exit(0)
}

// --history: print saved log and exit
if args.contains("--history") {
    let count = args.contains("--last")
        ? Int(args[safe: (args.firstIndex(of: "--last")! + 1)] ?? "20") ?? 20
        : nil
    // --since filtering: focus-history --history --since "2026-04-14"
    let sinceDate: Date? = {
        if let idx = args.firstIndex(of: "--since"),
           let val = args[safe: idx + 1] {
            let parser = DateFormatter()
            // Try full datetime first, then date-only
            for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
                parser.dateFormat = fmt
                if let d = parser.date(from: val) { return d }
            }
        }
        return nil
    }()

    if let data = try? String(contentsOfFile: logFile, encoding: .utf8) {
        var lines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let since = sinceDate {
            lines = lines.filter { line in
                let ts = String(line.prefix(19))
                if let d = dateFormatter.date(from: ts) { return d >= since }
                return true
            }
        }
        let output = count != nil ? Array(lines.suffix(count!)) : lines
        for line in output { print(line) }
    } else {
        print("No history yet. Run `focus-history --install` to start the background daemon.")
    }
    exit(0)
}

if args.contains("--help") {
    print("""
    focus-history - track which apps have focus

    Usage:
      focus-history                          Start recording in foreground (live output)
      focus-history --install                Install as background daemon (starts on login)
      focus-history --uninstall              Stop and remove the daemon
      focus-history --status                 Check if daemon is running
      focus-history --history                Print full saved history
      focus-history --history --last N       Print last N entries (default 20)
      focus-history --history --since DATE   Filter from date (e.g. "2026-04-14")
      focus-history --clear                  Clear saved history
      focus-history --help                   Show this help

    Log file: ~/.focus-history.log
    """)
    exit(0)
}

if args.contains("--clear") {
    try? "".write(toFile: logFile, atomically: true, encoding: .utf8)
    print("History cleared.")
    exit(0)
}

// --- Recording mode (foreground or daemon) ---

func rotateLogIfNeeded() {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFile),
          let size = attrs[.size] as? Int, size > maxLogSize else { return }
    // Keep the last half of the file
    if let data = try? String(contentsOfFile: logFile, encoding: .utf8) {
        let lines = data.components(separatedBy: "\n")
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? kept.write(toFile: logFile, atomically: true, encoding: .utf8)
    }
}

let fileHandle: FileHandle = {
    if !FileManager.default.fileExists(atPath: logFile) {
        FileManager.default.createFile(atPath: logFile, contents: nil)
    }
    let fh = FileHandle(forWritingAtPath: logFile)!
    fh.seekToEndOfFile()
    return fh
}()

var entryCount = 0

func log(_ message: String) {
    if !isDaemon { print(message) }
    fileHandle.write((message + "\n").data(using: .utf8)!)
    entryCount += 1
    if entryCount % 100 == 0 { rotateLogIfNeeded() }
}

// Log the currently active app at startup
if let app = NSWorkspace.shared.frontmostApplication {
    let name = app.localizedName ?? "Unknown"
    let pid = app.processIdentifier
    let bundle = app.bundleIdentifier ?? "-"
    log("\(dateFormatter.string(from: Date()))  \(name)  (pid: \(pid), bundle: \(bundle))")
}

let center = NSWorkspace.shared.notificationCenter
center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    let name = app.localizedName ?? "Unknown"
    let pid = app.processIdentifier
    let bundle = app.bundleIdentifier ?? "-"
    log("\(dateFormatter.string(from: Date()))  \(name)  (pid: \(pid), bundle: \(bundle))")
}

if !isDaemon {
    print("Recording focus changes... (Ctrl+C to stop)")
    print("History saved to \(logFile)")
    print("---")
}

// Keep the run loop alive
RunLoop.current.run()

// Safe array subscript
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
