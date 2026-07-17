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

    private let lifecycle = LifecycleStateMachine()
    private let snapshotEngine = SnapshotEngine(onError: { error in
        fputs("justasec: pipeline error — \(error)\n", stderr)
    })
    private let micSuppressionGate = MicSuppressionGate()
    private let speechSynth = SpeechSynthesizerActor()

    private var captureSession: (any AudioCaptureSessionProtocol)?
    private var whisperServer: WhisperServerProcess?
    private var startupTask: Task<Void, Never>?

    private lazy var orchestrator: PipelineOrchestrator = {
        PipelineOrchestrator(
            stateMachine: lifecycle,
            snapshotEngine: snapshotEngine,
            transcriber: WhisperTranscriber(),
            reasoner: OpenCodeClient(),
            speech: speechSynth,
            micGate: micSuppressionGate
        )
    }()

    private lazy var hotkeyController: HotkeyController = {
        HotkeyController { [weak self] in
            Task { @MainActor [weak self] in
                self?.orchestrator.handleTrigger()
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
        startupTask = Task { @MainActor in
            await performStartup()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        startupTask = nil
        hotkeyController.unregister()
        orchestrator.currentPipelineTask?.cancel()
        Task { @MainActor [weak self] in
            await self?.captureSession?.stop()
        }
        whisperServer?.terminate()
        whisperServer = nil
        fputs("justasec: terminated\n", stderr)
        AudioFeedback.dispose()
    }

    private func performStartup() async {
        do {
            try startWhisperServer()
        } catch {
            await failStartup("Startup failed: \(error)")
            return
        }

        guard await waitForWhisperReady() else {
            await failStartup("Whisper server not ready.")
            return
        }

        guard await startCapture() else {
            await failStartup("Capture failed to start.")
            return
        }

        guard registerHotkey() else {
            await failStartup("Hotkey registration failed.")
            return
        }

        do {
            try lifecycle.startupComplete()
        } catch {
            await failStartup("State transition failed.")
            return
        }

        fputs("justasec: ready\n", stderr)
    }

    private func failStartup(_ message: String) async {
        fputs("justasec: startup failed — \(message)\n", stderr)
        lifecycle.fail()
        await speechSynth.speak("Startup failed.", language: "en")
    }

    private func waitForWhisperReady() async -> Bool {
        guard let server = whisperServer else { return false }
        return await server.checkReadiness(timeout: 10.0)
    }

    private func startCapture() async -> Bool {
        let engine = snapshotEngine
        let gate = micSuppressionGate
        let session = AudioCaptureSession(
            onSample: { payload in
                guard !gate.shouldDiscard(source: payload.source) else { return }
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

        do {
            try await session.start()
            fputs("justasec: audio capture started\n", stderr)
            return true
        } catch let error as AudioCaptureError {
            fputs("justasec: capture failed to start - \(error)\n", stderr)
            return false
        } catch {
            fputs("justasec: capture failed to start - \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    private func registerHotkey() -> Bool {
        fputs("justasec: registering hotkey Control-Option-Space\n", stderr)
        guard hotkeyController.register() else {
            fputs("justasec: hotkey registration failed\n", stderr)
            return false
        }
        fputs("justasec: hotkey registered\n", stderr)
        return true
    }

    private func startWhisperServer() throws {
        let config = WhisperServerConfig()
        let server = WhisperServerProcess(config: config)
        try server.validate()
        try server.launch()
        self.whisperServer = server
        fputs("justasec: whisper server started\n", stderr)
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
