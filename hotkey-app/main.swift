// ClaudeApproveAll — global hotkey daemon
// Registers Cmd+Shift+A globally via Carbon RegisterEventHotKey.
// Does NOT require Accessibility permission.
// Runs as a background (LSUIElement) app with no Dock icon.
// When triggered, runs ~/.claude/hooks/toggle-approve-all.sh

import Cocoa
import Carbon

func runToggleScript() {
    let script = NSHomeDirectory() + "/.claude/hooks/toggle-approve-all.sh"
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [script]
    try? task.run()
}

// Carbon event handler — called when the hotkey fires
let hotKeyHandler: EventHandlerUPP = { _, event, _ -> OSStatus in
    runToggleScript()
    return noErr
}

// Register Cmd+Shift+A as a system-wide hotkey via Carbon.
// Key code 0 = 'a'; cmdKey | shiftKey = 768
var hotKeyRef: EventHotKeyRef?
let hotKeyID = EventHotKeyID(signature: OSType(0x434C4153), id: 1) // 'CLAS'
let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                              eventKind: UInt32(kEventHotKeyPressed))

var handlerRef: EventHandlerRef?
InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, [eventSpec], nil, &handlerRef)

let status = RegisterEventHotKey(
    0,           // key code for 'a'
    UInt32(cmdKey | shiftKey),
    hotKeyID,
    GetApplicationEventTarget(),
    0,
    &hotKeyRef
)

if status != noErr {
    fputs("ClaudeApproveAll: failed to register hotkey (OSStatus \(status))\n", stderr)
    exit(1)
}

NSApplication.shared.run()
