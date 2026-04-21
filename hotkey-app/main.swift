// ClaudeApproveAll — global hotkey daemon
// Registers Cmd+Shift+A globally via CGEventTap.
// Runs as a background (LSUIElement) app with no Dock icon.
// When triggered, runs ~/.claude/hooks/toggle-approve-all.sh

import Cocoa
import Carbon

// Cmd(1 << 20) + Shift(1 << 17) = 0x120000
let TARGET_MODIFIERS = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)

// Virtual key code for 'a'
let KEY_A: CGKeyCode = 0

func runToggleScript() {
    let script = NSHomeDirectory() + "/.claude/hooks/toggle-approve-all.sh"
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [script]
    task.launch()
}

let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard type == .keyDown else { return Unmanaged.passRetained(event) }
    let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if keyCode == KEY_A && flags == TARGET_MODIFIERS {
        runToggleScript()
        // Consume the event so it doesn't reach the focused app
        return nil
    }
    return Unmanaged.passRetained(event)
}

// CGEventTap requires Accessibility permission (System Settings → Privacy → Accessibility).
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: callback,
    userInfo: nil
)

guard let tap = tap else {
    // Prompt the user to grant Accessibility access
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    // Exit — the user must re-launch after granting access
    print("ClaudeApproveAll: Accessibility permission required. Grant it in System Settings and relaunch.")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
NSApplication.shared.run()
