import AppKit
import Darwin

let appDelegate = JustasecApp()
guard appDelegate.validateSystemDependencies() else {
    fputs("justasec: dependency validation failed\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(JustasecApp.preferredActivationPolicy)

// Signal handling invariant:
// 1. signal(SIG_IGN) prevents default termination before the dispatch sources
//    activate. DispatchSource.makeSignalSource internally calls sigaction to
//    install the framework's own handler, overriding SIG_IGN.
// 2. Setup occurs after NSApplication.shared to be the final handler, overriding
//    any signal(2) calls made by AppKit during init.
// 3. All signals route through NSApp.terminate which triggers
//    applicationShouldTerminate that handles async cleanup and replies with
//    terminateLater. No main-actor blocking or unbounded waits.
//    A finite 4-second fallback inside the cleanup task prevents hangs.
// 4. atexit (registered by WhisperServerProcess) is invoked by exit(0) as a
//    last resort to terminate the child whisper-server before host exit.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
WhisperServerProcess.setupGlobalCleanup()

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler { NSApp.terminate(nil) }
sigintSource.resume()

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler { NSApp.terminate(nil) }
sigtermSource.resume()

app.run()
