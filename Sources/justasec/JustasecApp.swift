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
    private let snapshotEngine = SnapshotEngine(onError: { error in
        fputs("justasec: pipeline error — \(error)\n", stderr)
    })

    private var captureSession: (any AudioCaptureSessionProtocol)?
    private var whisperServer: WhisperServerProcess?

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

            try startWhisperServer()
            fputs("justasec: whisper server started\n", stderr)

            startCapture()
            fputs("justasec: registering hotkey Control-Option-Space\n", stderr)
            if hotkeyController.register() {
                fputs("justasec: hotkey registered\n", stderr)
            } else {
                fputs("justasec: warning - hotkey registration failed\n", stderr)
            }
            fputs("justasec: ready\n", stderr)
        } catch {
            fputs("justasec: startup failed — \(error)\n", stderr)
            lifecycle.fail()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyController.unregister()
        Task { @MainActor [weak self] in
            await self?.captureSession?.stop()
        }
        whisperServer?.terminate()
        whisperServer = nil
        fputs("justasec: terminated\n", stderr)
        AudioFeedback.dispose()
    }

    private func startCapture() {
        let engine = snapshotEngine
        let session = AudioCaptureSession(
            onSample: { payload in
                Task { await engine.ingestPayload(payload) }
            },
            onError: { error in
                fputs("justasec: capture error: \(error)\n", stderr)
            },
            onFormatChange: { format, source in
                fputs("justasec: \(source.rawValue) format change: \(Int(format.sampleRate))Hz \(format.channelCount)ch\n", stderr)
            }
        )
        self.captureSession = session

        Task {
            do {
                try await session.start()
                fputs("justasec: audio capture started\n", stderr)
            } catch let error as AudioCaptureError {
                fputs("justasec: capture failed to start - \(error)\n", stderr)
                self.lifecycle.fail()
            } catch {
                fputs("justasec: capture failed to start - \(error.localizedDescription)\n", stderr)
                self.lifecycle.fail()
            }
        }
    }

    private func handleHotkey() {
        if lifecycle.trigger() {
            AudioFeedback.play(.trigger)
        } else {
            AudioFeedback.play(.busy)
        }
    }

    private func startWhisperServer() throws {
        let config = WhisperServerConfig()
        let server = WhisperServerProcess(config: config)
        try server.validate()
        try server.launch()
        self.whisperServer = server

        Task {
            let ready = await server.checkReadiness(timeout: 10.0)
            if ready {
                fputs("justasec: whisper server ready\n", stderr)
            } else {
                fputs("justasec: warning — whisper server not ready\n", stderr)
            }
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
