import AppKit
import Foundation
import Dispatch
import os.lock

@MainActor
public final class AskamiApp: NSObject, NSApplicationDelegate {
    public static let bundleIdentifier = "com.sebastianlungu.askami"
    public static let preferredActivationPolicy: NSApplication.ActivationPolicy = .accessory

    private static let requiredTools: [(name: String, path: String, arg: String)] = [
        ("swift", "/usr/bin/swift", "--version"),
        ("xcodebuild", "/usr/bin/xcodebuild", "-version"),
        ("opencode", "/opt/homebrew/bin/opencode", "--version"),
        ("whisper-server", "/opt/homebrew/bin/whisper-server", "--help"),
        ("espeak-ng", "/opt/homebrew/bin/espeak-ng", "--version"),
    ]

    public let dockStatusPresenter = DockStatusPresenter(isDockPresentationEnabled: false)
    internal lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.setAccessibilityLabel("Askami")
        return item
    }()
    private lazy var statusLabelItem = NSMenuItem(title: "Status: Launching", action: nil, keyEquivalent: "")
    private lazy var shortcutLabelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lifecycle = LifecycleStateMachine()
    private let snapshotEngine = SnapshotEngine(onError: { error in
        fputs("askami: pipeline error — \(error)\n", stderr)
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
                let success = hotkeyController.replaceShortcut(with: shortcut)
                if success { updateShortcutLabel() }
                return success
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
        setupStatusItem()
        dockStatusPresenter.onTransition = { [weak self] status in
            self?.updateStatusItem(for: status)
        }
        startupTask = Task { @MainActor in
            await performStartup()
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        startupTask?.cancel()
        startupTask = nil
        hotkeyController.unregister()
        orchestrator.currentPipelineTask?.cancel()
        AudioFeedback.shared.stop()

        let server = whisperServer
        whisperServer = nil
        let session = captureSession
        captureSession = nil

        Task {
            let fallback = Task.detached { [done = terminationDone] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !done.withLock({ $0 }) else { return }
                fputs("askami: force exit after timeout\n", stderr)
                exit(1)
            }

            if let session = session {
                await session.stop()
            }
            await server?.terminateAsync()
            terminationDone.withLock { $0 = true }
            fallback.cancel()

            fputs("askami: terminated\n", stderr)
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
            AudioFeedback.shared.stop()
            whisperServer?.forceTerminate()
            whisperServer = nil
            captureSession = nil
        }
        fputs("askami: terminated\n", stderr)
    }

    private func setupStatusItem() {
        statusLabelItem.isEnabled = false
        shortcutLabelItem.isEnabled = false
        updateShortcutLabel()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command

        let quitItem = NSMenuItem(
            title:     "Quit Askami",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command

        let menu = NSMenu()
        menu.addItem(statusLabelItem)
        menu.addItem(shortcutLabelItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        updateStatusItem(for: dockStatusPresenter.currentStatus)
    }

    internal func updateShortcutLabel() {
        shortcutLabelItem.title = "Shortcut: \(hotkeyController.currentShortcut.displayString)"
    }

    @objc private func openSettings() {
        settingsPanelController.showPanel()
    }

    private func updateStatusItem(for status: DockStatus) {
        let name = DockStatusPresenter.symbolNames[status] ?? "questionmark"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: status.rawValue)
        img?.isTemplate = true
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        statusItem.button?.image = img?.withSymbolConfiguration(cfg)
        statusItem.button?.toolTip = "Askami — \(status.rawValue)"
        statusItem.button?.setAccessibilityLabel("Askami, \(status.rawValue)")
        statusLabelItem.title = "Status: \(status.rawValue)"
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
        fputs("askami: ready\n", stderr)
    }

    private func failStartup(_ message: String) async {
        fputs("askami: startup failed — \(message)\n", stderr)
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
                fputs("askami: capture error: \(error)\n", stderr)
                Task { @MainActor in
                    self?.orchestrator.currentPipelineTask?.cancel()
                    self?.captureSession = nil
                    self?.lifecycle.fail()
                    self?.dockStatusPresenter.transition(to: .error)
                    _ = await self?.speechSynth.speak("Capture failed.", language: "en")
                }
            },
            onFormatChange: { format, source in
                fputs("askami: \(source.rawValue) format change: \(Int(format.sampleRate))Hz \(format.channelCount)ch\n", stderr)
            }
        )
        self.captureSession = session

        do {
            try await session.start()
            fputs("askami: audio capture started\n", stderr)
            return true
        } catch let error as AudioCaptureError {
            fputs("askami: capture failed to start - \(error)\n", stderr)
            return false
        } catch {
            fputs("askami: capture failed to start - \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    private func registerHotkey() -> Bool {
        fputs("askami: registering hotkey \(hotkeyController.currentShortcut.displayString)\n", stderr)
        guard hotkeyController.register() else {
            fputs("askami: hotkey registration failed\n", stderr)
            return false
        }
        fputs("askami: hotkey registered\n", stderr)
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
        fputs("askami: whisper server started\n", stderr)
    }

    private func checkToolAvailable(at path: String, with argument: String) -> Bool {
        let resolved = resolveToolPath(path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
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

    private func resolveToolPath(_ path: String) -> String {
        guard !FileManager.default.isExecutableFile(atPath: path) else { return path }
        let toolName = (path as NSString).lastPathComponent
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return path }
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(toolName)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return path
    }
}
