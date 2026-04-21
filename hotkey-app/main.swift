// ClaudeApproveAll — global hotkey daemon
// Listens for Cmd+Ctrl+B system-wide via CGEventTap (listenOnly).
// Requires Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring).
// The app auto-prompts on first launch.
// Logs to ~/Library/Logs/ClaudeApproveAll.log

import Cocoa

let logPath = NSHomeDirectory() + "/Library/Logs/ClaudeApproveAll.log"

func log(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logPath),
       let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
}

func runToggleScript() {
    log("hotkey fired — running toggle script")
    let script = NSHomeDirectory() + "/.claude/hooks/toggle-approve-all.sh"
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [script]
    try? task.run()
}

// Key code 11 = 'b'; Cmd+Ctrl modifiers
let KEY_B: CGKeyCode = 11
let TARGET_FLAGS = CGEventFlags(rawValue:
    CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue)

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .keyDown {
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate])
        let key   = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if key == KEY_B && flags == TARGET_FLAGS {
            runToggleScript()
        }
    }
    return Unmanaged.passRetained(event)
}

// Attempt to create the event tap.
// listenOnly = observe only (cannot suppress events) — this still needs Input Monitoring,
// but is the minimal permission needed and the correct TCC service for this use case.
func createTap() -> CFMachPort? {
    return CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .tailAppendEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
        callback: callback,
        userInfo: nil
    )
}

guard let tap = createTap() else {
    log("tapCreate returned nil — Input Monitoring permission not granted. Prompting user.")
    // Open System Settings to the right pane
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    NSWorkspace.shared.open(url)
    let uid = getuid()
    let kickstart = "launchctl kickstart -k gui/\(uid)/com.claudecodehooks.approve-all-hotkey"
    fputs("ClaudeApproveAll: Grant Input Monitoring in System Settings → Privacy & Security → Input Monitoring, then run:\n  \(kickstart)\n", stderr)
    // Use alerter (already installed) to show a persistent prompt
    let alerter = "/opt/homebrew/bin/alerter"
    if FileManager.default.fileExists(atPath: alerter) {
        let task = Process()
        task.launchPath = alerter
        task.arguments = [
            "--title", "ClaudeApproveAll — action required",
            "--message", "Grant Input Monitoring permission, then run in terminal: \(kickstart)",
            "--close-label", "OK",
            "--sender", "com.apple.Terminal",
            "--timeout", "0"
        ]
        try? task.run()
    }
    Thread.sleep(forTimeInterval: 2)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
log("started — Cmd+Ctrl+B active (listenOnly CGEventTap)")
NSApplication.shared.run()
