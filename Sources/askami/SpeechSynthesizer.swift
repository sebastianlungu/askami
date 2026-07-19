import Foundation
@preconcurrency import AVFoundation
import KokoroCoreML
import os.lock

public let defaultTTSVoice = "af_heart"
public var espeakExecutablePath: String {
    let defaultPath = "/opt/homebrew/bin/espeak-ng"
    guard !FileManager.default.isExecutableFile(atPath: defaultPath) else { return defaultPath }
    guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return defaultPath }
    for dir in pathEnv.split(separator: ":") {
        let candidate = "\(dir)/espeak-ng"
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return defaultPath
}

/// CPU-only CoreML inference: ANE/E5RT emits a non-fatal shape fallback on this
/// hardware; CPU output was verified byte-identical and faster in local probes.
public let kokoroUseCPUOnly = true

// MARK: - Public driver protocol
public protocol SpeechDriverProtocol: AnyObject, Sendable {
    func speak(_ text: String, language: String?, beforePlayback: PlaySoundEffect?) async -> SpeechResult
    func stop()
}

public extension SpeechDriverProtocol {
    func speak(_ text: String, language: String?) async -> SpeechResult {
        await speak(text, language: language, beforePlayback: nil)
    }
}

public struct KokoroLanguageProfile: Sendable, Equatable {
    public let voice: String
    public let espeakVoice: String?

    public static func resolve(_ language: String?) -> Self {
        let key = language?.lowercased().replacingOccurrences(of: "_", with: "-") ?? "en"
        switch key {
        case "en", "english", "en-us", "en-gb": return Self(voice: defaultTTSVoice, espeakVoice: nil)
        case "pt", "portuguese", "pt-br": return Self(voice: "pf_dora", espeakVoice: "pt-br")
        case "es", "spanish": return Self(voice: "ef_dora", espeakVoice: "es")
        case "fr", "french", "fr-fr": return Self(voice: "ff_siwis", espeakVoice: "fr-fr")
        case "it", "italian": return Self(voice: "if_sara", espeakVoice: "it")
        case "hi", "hindi": return Self(voice: "hf_alpha", espeakVoice: "hi")
        case "ja", "japanese": return Self(voice: "jf_alpha", espeakVoice: "ja")
        case "zh", "chinese", "mandarin", "zh-cn": return Self(voice: "zf_xiaoxiao", espeakVoice: "cmn")
        default: return Self(voice: defaultTTSVoice, espeakVoice: espeakVoice(for: key))
        }
    }

    private static func espeakVoice(for language: String) -> String {
        let aliases = [
            "arabic": "ar", "catalan": "ca", "czech": "cs", "danish": "da",
            "dutch": "nl", "finnish": "fi", "german": "de", "greek": "el",
            "hebrew": "he", "hungarian": "hu", "indonesian": "id",
            "korean": "ko", "norwegian": "no", "polish": "pl", "romanian": "ro",
            "russian": "ru", "swedish": "sv", "thai": "th", "turkish": "tr",
            "ukrainian": "uk", "vietnamese": "vi",
        ]
        return aliases[language] ?? language
    }
}

public enum ESpeakPhonemizer {
    public static func phonemize(_ text: String, voice: String) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: espeakExecutablePath) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: espeakExecutablePath)
        process.arguments = ["-q", "--ipa", "-v", voice]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let ipa = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !ipa.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ipa
    }
}

// MARK: - Internal timeout hinting
package protocol TimeoutHinting {
    var timeoutHint: TimeInterval { get }
}

// MARK: - Kokoro production driver

    public final class KokoroSpeechDriver: SpeechDriverProtocol, @unchecked Sendable {
    private let voice: String
    private let modelDirectory: URL
    private var engine: KokoroEngine?
    private var session: PlaybackSession?
    private var speakTask: Task<Void, Never>?
    private let _stopRequested = OSAllocatedUnfairLock(initialState: false)

    /// Injectable engine factory for testing. When non-nil, bypasses real engine
    /// construction and download logic entirely.
    package var _engineFactory: (@Sendable (URL, Bool) throws -> KokoroEngine)?

    public init(
        voice: String = defaultTTSVoice,
        modelDirectory: URL? = nil
    ) {
        self.voice = voice
        self.modelDirectory = modelDirectory ?? KokoroEngine.defaultModelDirectory
    }

    package var timeoutHint: TimeInterval {
        if engine != nil || KokoroEngine.isDownloaded(at: modelDirectory) {
            return 30
        }
        return 300
    }

    public func speak(_ text: String, language: String? = nil,
                      beforePlayback: PlaySoundEffect? = nil) async -> SpeechResult {
        _stopRequested.withLock { $0 = false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                speakTask = Task.detached { [self] in
                    let result = await self.performSpeaking(
                        text, language: language, beforePlayback: beforePlayback)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: { [weak self] in
            self?.stop()
        }
    }

    private func performSpeaking(_ text: String, language: String?, beforePlayback: PlaySoundEffect?) async -> SpeechResult {
        let engine: KokoroEngine
        do {
            engine = try loadOrDownloadEngine()
        } catch is CancellationError {
            return .cancelled
        } catch {
            fputs("askami: Kokoro model not available — \(error)\n", stderr)
            return .failed
        }
        guard let session = PlaybackSession() else { return .failed }
        self.session = session
        let stream: AsyncStream<SpeakEvent>
        do {
            stream = try await makeStream(engine: engine, text: text, language: language)
        } catch {
            fputs("askami: Kokoro speak failed — \(error)\n", stderr)
            await session.cancel()
            return .failed
        }
        var hasAudio = false
        for await event in stream where !_stopRequested.withLock({ $0 }) {
            switch event {
            case .audio(let buffer):
                if !hasAudio {
                    await beforePlayback?()
                    guard !_stopRequested.withLock({ $0 }), !Task.isCancelled else {
                        await session.cancel()
                        return .cancelled
                    }
                }
                guard await session.enqueue(buffer) else {
                    await session.cancel()
                    return .failed
                }
                hasAudio = true
            case .chunkFailed(let error):
                fputs("askami: synthesis chunk failed — \(error)\n", stderr)
                await session.cancel()
                return .failed
            }
        }
        guard hasAudio else {
            await session.cancel()
            self.session = nil
            return _stopRequested.withLock({ $0 }) ? .cancelled : .failed
        }
        if !_stopRequested.withLock({ $0 }) {
            await session.drain()
        }
        await session.cancel()
        self.session = nil
        return _stopRequested.withLock({ $0 }) ? .cancelled : .completed
    }

    private func makeStream(
        engine: KokoroEngine,
        text: String,
        language: String?
    ) async throws -> AsyncStream<SpeakEvent> {
        let profile = KokoroLanguageProfile.resolve(language)
        let selectedVoice = profile.espeakVoice == nil ? voice : profile.voice
        guard engine.availableVoices.contains(selectedVoice) else {
            throw KokoroError.voiceNotFound(selectedVoice)
        }
        guard let espeakVoice = profile.espeakVoice else {
            return try engine.speak(text, voice: selectedVoice, paceToRealtime: true)
        }
        let ipa = try ESpeakPhonemizer.phonemize(text, voice: espeakVoice)
        let result = try await Self.synthesizeIPA(
            engine: engine,
            ipa: ipa,
            voice: selectedVoice
        )
        let buffer = try Self.makeBuffer(samples: result.samples)
        return AsyncStream { continuation in
            continuation.yield(.audio(buffer))
            continuation.finish()
        }
    }

    private static func synthesizeIPA(
        engine: KokoroEngine,
        ipa: String,
        voice: String
    ) async throws -> SynthesisResult {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do {
                    continuation.resume(
                        returning: try engine.synthesize(ipa: ipa, voice: voice)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.stackSize = 8 * 1024 * 1024
            thread.start()
        }
    }

    private static func makeBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let count = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: KokoroEngine.audioFormat,
            frameCapacity: count
        ), let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        buffer.frameLength = count
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private func loadOrDownloadEngine() throws -> KokoroEngine {
        if let engine { return engine }
        if let factory = _engineFactory {
            let eng = try factory(modelDirectory, kokoroUseCPUOnly)
            engine = eng
            return eng
        }
        if Task.isCancelled { throw CancellationError() }
        let downloaded = KokoroEngine.isDownloaded(at: modelDirectory)
        if !downloaded {
            fputs("askami: downloading KokoroCoreML model (~99MB)...\n", stderr)
            do {
                try KokoroEngine.download(to: modelDirectory) { pct in
                    if pct == 1.0 { fputs("askami: Kokoro download complete\n", stderr) }
                }
            } catch {
                fputs("askami: Kokoro download failed — \(error)\n", stderr)
                throw error
            }
            if Task.isCancelled { throw CancellationError() }
        }
        if Task.isCancelled { throw CancellationError() }
        let eng = try KokoroEngine(modelDirectory: modelDirectory, forceCPU: kokoroUseCPUOnly)
        engine = eng
        return eng
    }

    public func stop() {
        _stopRequested.withLock { $0 = true }
        speakTask?.cancel()
        let s = session
        session = nil
        Task { await s?.cancel() }
    }
}

extension KokoroSpeechDriver: TimeoutHinting {}

// MARK: - Test driver

public final class TestSpeechDriver: SpeechDriverProtocol, @unchecked Sendable {
    public var capturedText: String?
    public var capturedLanguage: String?
    public var stopCallCount = 0
    public var autoCompleteDelay: TimeInterval = 0
    public var autoCompleteResult: SpeechResult = .completed
    public var timeoutHintOverride: TimeInterval = 30
    public var shouldStreamFail = false
    private var continuation: CheckedContinuation<SpeechResult, Never>?

    public init() {}

    public func speak(_ text: String, language: String? = nil,
                      beforePlayback: PlaySoundEffect? = nil) async -> SpeechResult {
        if shouldStreamFail { return .failed }
        capturedText = text
        capturedLanguage = language
        await beforePlayback?()
        if Task.isCancelled { return .cancelled }
        if autoCompleteDelay >= 0 {
            if autoCompleteDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(autoCompleteDelay * 1_000_000_000))
            }
            return autoCompleteResult
        }
        return await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    public func stop() {
        stopCallCount += 1
        continuation?.resume(returning: .cancelled)
        continuation = nil
    }

    public func fireCompletion(_ result: SpeechResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

extension TestSpeechDriver: TimeoutHinting {
    package var timeoutHint: TimeInterval { timeoutHintOverride }
}

// MARK: - Actor state

private enum SpeechState {
    case idle
    case speaking(id: UUID, continuation: CheckedContinuation<SpeechResult, Never>)
}

// MARK: - Actor

@MainActor
public final class SpeechSynthesizerActor: @preconcurrency SpeechSynthesizerProtocol {
    private let driver: SpeechDriverProtocol
    private var state: SpeechState = .idle
    private var speakTimeoutTask: Task<Void, Never>?

    public static let speakTimeout: TimeInterval = 30

    public init(driver: SpeechDriverProtocol = KokoroSpeechDriver()) {
        self.driver = driver
    }

    @discardableResult
    public func speak(_ text: String, language: String?,
                      beforePlayback: PlaySoundEffect?) async -> SpeechResult {
        guard case .idle = state else { return .failed }

        let speakId = UUID()
        let timeout = (driver as? TimeoutHinting)?.timeoutHint ?? Self.speakTimeout

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<SpeechResult, Never>) in
                state = .speaking(id: speakId, continuation: cont)

                Task { @MainActor [weak self, driver, text] in
                    guard let self, case .speaking(let currentId, _) = self.state,
                          currentId == speakId else { return }
                    let result = await driver.speak(
                        text, language: language, beforePlayback: beforePlayback)
                    guard case .speaking(let currentId2, _) = self.state,
                          currentId2 == speakId else { return }
                    self.state = .idle
                    self.speakTimeoutTask?.cancel()
                    self.speakTimeoutTask = nil
                    cont.resume(returning: result)
                }

                speakTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.timeoutSpeak()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelSpeak()
            }
        }
    }

    public func stop() {
        guard case .speaking(_, let cont) = state else { return }
        driver.stop()
        state = .idle
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .cancelled)
    }

    private func cancelSpeak() {
        guard case .speaking(_, let cont) = state else { return }
        driver.stop()
        state = .idle
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .cancelled)
    }

    private func timeoutSpeak() {
        guard case .speaking(_, let cont) = state else { return }
        driver.stop()
        state = .idle
        speakTimeoutTask = nil
        cont.resume(returning: .failed)
    }
}
