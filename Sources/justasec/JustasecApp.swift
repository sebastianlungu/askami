import AppKit
import Foundation

@MainActor
public final class JustasecApp: NSObject, NSApplicationDelegate {
    public static let bundleIdentifier = "com.sebastianlungu.justasec"

    private static let requiredTools: [(name: String, path: String, arg: String)] = [
        ("swift", "/usr/bin/swift", "--version"),
        ("xcodebuild", "/usr/bin/xcodebuild", "-version"),
        ("opencode", "/opt/homebrew/bin/opencode", "--version"),
        ("whisper-server", "/opt/homebrew/bin/whisper-server", "--help"),
    ]

    private var lifecycle = LifecycleStateMachine()

    private lazy var hotkeyController: HotkeyController = {
        HotkeyController { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkey()
            }
        }
    }()

    public override init() {
        super.init()
    }

    public func validateSystemDependencies() -> Bool {
        Self.requiredTools.allSatisfy { tool in
            checkToolAvailable(at: tool.path, with: tool.arg)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try lifecycle.startupComplete()
            fputs("justasec: ready\n", stderr)
            fputs("justasec: registering hotkey Control-Option-Space\n", stderr)
            if hotkeyController.register() {
                fputs("justasec: hotkey registered\n", stderr)
            } else {
                fputs("justasec: warning - hotkey registration failed\n", stderr)
            }
        } catch {
            fputs("justasec: startup failed\n", stderr)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyController.unregister()
        fputs("justasec: terminated\n", stderr)
        AudioFeedback.dispose()
    }

    private func handleHotkey() {
        if lifecycle.trigger() {
            AudioFeedback.play(.trigger)
        } else {
            AudioFeedback.play(.busy)
        }
    }

    private func checkToolAvailable(at path: String, with argument: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [argument]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
