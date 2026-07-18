import AppKit
import Foundation
import Dispatch
import os.lock

@MainActor
public final class JustasecApp: NSObject, NSApplicationDelegate {
    public static let bundleIdentifier = "com.sebastianlungu.justasec"
    public static let preferredActivationPolicy: NSApplication.ActivationPolicy = .regular

    private static let requiredTools: [(name: String, path: String, arg: String)] = [
        ("swift", "/usr/bin/swift", "--version"),
        ("xcodebuild", "/usr/bin/xcodebuild", "-version"),
        ("opencode", "/opt/homebrew/bin/opencode", "--version"),
        ("whisper-server", "/opt/homebrew/bin/whisper-server", "--help"),
    ]

    public let dockStatusPresenter = DockStatusPresenter()
    private let lifecycle = LifecycleStateMachine()
    private let snapshotEngine = SnapshotEngine(onError: { error in
        fputs("justasec: pipeline error — \(error)\n", stderr)
    })
    private let micSuppressionGate = MicSuppressionGate()
    private let speechSynth = SpeechSynthesizerActor()

    private var captureSession: (any AudioCaptureSessionProtocol)?
    private var whisperServer: WhisperServerProcess?
    private var startupTask: Task<Void, Never>?

    private var isTerminating = false
    private let terminationDone = OSAllocatedUnfairLock(initialState: false)

    private lazy var orchestrator: PipelineOrchestrator = {
        PipelineOrchestrator(
            stateMachine: lifecycle,
            dependencies: PipelineDependencies(
                pipeline: .init(
                    snapshotEngine: snapshotEngine,
                    transcriber: WhisperTranscriber(),
                    reasoner: OpenCodeClient()
                ),
                speech: speechSynth,
                feedback: .init(micGate: micSuppressionGate)
            ),
            presenter: dockStatusPresenter
        )
    }()

    private lazy var hotkeyController: HotkeyController = {
        HotkeyController(
            handler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.orchestrator.handleTrigger()
                }
            },
            registrar: RealCarbonHotkeyRegistrar(),
            preferenceStore: RealShortcutPreferenceStore()
        )
    }()

    public lazy var settingsPanelController: SettingsPanelController = {
        SettingsPanelController(
            initialShortcut: hotkeyController.currentShortcut,
            onReplace: { [weak self] shortcut in
                guard let self else { return false }
                return hotkeyController.replaceShortcut(with: shortcut)
            },
            onTerminate: { NSApp.terminate(nil) }
        )
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
        setupMenu()
        startupTask = Task { @MainActor in
            await performStartup()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsPanelController.showPanel()
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        startupTask?.cancel()
        startupTask = nil
        hotkeyController.unregister()
        orchestrator.currentPipelineTask?.cancel()
        AudioFeedback.dispose()

        let server = whisperServer
        whisperServer = nil
        let session = captureSession
        captureSession = nil

        Task {
            let fallback = Task.detached { [done = terminationDone] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !done.withLock({ $0 }) else { return }
                fputs("justasec: force exit after timeout\n", stderr)
                exit(1)
            }

            if let session = session {
                await session.stop()
            }
            await server?.terminateAsync()
            terminationDone.withLock { $0 = true }
            fallback.cancel()

            fputs("justasec: terminated\n", stderr)
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        dockStatusPresenter.cleanup()
        if !isTerminating {
            isTerminating = true
            startupTask?.cancel()
            hotkeyController.unregister()
            orchestrator.currentPipelineTask?.cancel()
            AudioFeedback.dispose()
            whisperServer?.forceTerminate()
            whisperServer = nil
            captureSession = nil
        }
        fputs("justasec: terminated\n", stderr)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit JustASec",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func performStartup() async {
        do {
            try await startWhisperServer()
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

        dockStatusPresenter.transition(to: .listening)
        fputs("justasec: ready\n", stderr)
    }

    private func failStartup(_ message: String) async {
        fputs("justasec: startup failed — \(message)\n", stderr)
        lifecycle.fail()
        dockStatusPresenter.transition(to: .error)
        _ = await speechSynth.speak("Startup failed.", language: "en")
    }

    private func waitForWhisperReady() async -> Bool {
        guard let server = whisperServer else { return false }
        return await server.checkReadiness(timeout: 10.0)
    }

    private func startCapture() async -> Bool {
        let session = AudioCaptureSession(
            onSample: { [weak self] payload in
                guard let self, !self.micSuppressionGate.shouldDiscard(source: payload.source) else { return }
                Task { await self.snapshotEngine.ingestPayload(payload) }
            },
            onError: { [weak self] error in
                fputs("justasec: capture error: \(error)\n", stderr)
                Task { @MainActor in
                    self?.captureSession = nil
                    self?.lifecycle.fail()
                    self?.dockStatusPresenter.transition(to: .error)
                    _ = await self?.speechSynth.speak("Capture failed.", language: "en")
                }
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

    private func startWhisperServer() async throws {
        let config = WhisperServerConfig()
        let server = WhisperServerProcess(config: config)
        try await Task.detached {
            try server.validate()
            try server.launch()
        }.value
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
