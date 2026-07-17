import AppKit
import Darwin

let appDelegate = JustasecApp()
guard appDelegate.validateSystemDependencies() else {
    fputs("justasec: dependency validation failed\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)

// Signal handling invariant:
// 1. signal(SIG_IGN) prevents default termination before the dispatch sources
//    activate. DispatchSource.makeSignalSource internally calls sigaction to
//    install the framework's own handler, overriding SIG_IGN.
// 2. Setup occurs after NSApplication.shared to be the final handler, overriding
//    any signal(2) calls made by AppKit during init.
// 3. The handler calls exit(0) after printing termination diagnostic. This is
//    safe because the handler runs on the main queue, not at signal-level context.
//    Carbon hotkey and AudioToolbox sound resources are cleaned by process exit.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    fputs("justasec: terminated\n", stderr)
    exit(0)
}
sigintSource.resume()

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    fputs("justasec: terminated\n", stderr)
    exit(0)
}
sigtermSource.resume()

app.run()
