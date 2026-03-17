import AppKit
import CLibGhostty

// Initialize libghostty
let initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
guard initResult == 0 else {
    fputs("ghostlight: failed to initialize libghostty (\(initResult))\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
