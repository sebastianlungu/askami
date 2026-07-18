import Foundation
import CoreMedia
import os.lock
@preconcurrency import AVFoundation

// MARK: - Protocol definitions for dependency injection

public protocol SnapshotEngineProtocol: Sendable {
    func ingestPayload(_ payload: AudioSamplePayload) async
    func snapshot(before timestamp: CMTime, duration: TimeInterval) async throws -> Data?
    func currentCaptureTime() async -> CMTime?
}

extension SnapshotEngine: SnapshotEngineProtocol {}

public protocol TranscriberProtocol: Sendable {
    func transcribe(wavData: Data, timeout: TimeInterval) async throws -> WhisperTranscriptionResult
}

extension WhisperTranscriber: TranscriberProtocol {}

public protocol ReasonerProtocol: Sendable {
    func analyze(transcript: String, language: String?) async throws -> OpenCodeResult
}

extension OpenCodeClient: ReasonerProtocol {}

public enum SpeechResult: Sendable, Equatable {
    case completed
    case cancelled
    case failed
}

public protocol SpeechSynthesizerProtocol: AnyObject, Sendable {
    @discardableResult
    func speak(_ text: String, language: String?) async -> SpeechResult
    func stop()
}

public protocol ClockProtocol: Sendable {
    func now() -> TimeInterval
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemClock: ClockProtocol, Sendable {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Pipeline errors

public enum PipelineError: Error, Sendable, Equatable {
    case silence
    case transcriptionFailed(String)
    case reasoningFailed(String)
    case speechFailed(String)
    case captureFailed(String)
    case stateError(String)
}

// MARK: - Timing snapshot

public struct TimingSnapshot: Sendable, Equatable {
    public var snapshotElapsed: TimeInterval?
    public var transcriptionElapsed: TimeInterval?
    public var reasoningElapsed: TimeInterval?
    public var totalElapsed: TimeInterval?

    public init(
        snapshotElapsed: TimeInterval? = nil,
        transcriptionElapsed: TimeInterval? = nil,
        reasoningElapsed: TimeInterval? = nil,
        totalElapsed: TimeInterval? = nil
    ) {
        self.snapshotElapsed = snapshotElapsed
        self.transcriptionElapsed = transcriptionElapsed
        self.reasoningElapsed = reasoningElapsed
        self.totalElapsed = totalElapsed
    }
}

// MARK: - Log function type

public typealias LogFunction = @Sendable (String) -> Void

// MARK: - Pipeline events for test recording

public enum PipelineEvent: Sendable, Equatable {
    case status(DockStatus)
    case suppressionStart
    case suppressionEnd
    case chime(ChimeType)
    case sleep(TimeInterval)
    case speechBegin
    case speechResult(SpeechResult)
    case lifecycleReady
}

public final class EventRecorder: Sendable {
    private let _events: OSAllocatedUnfairLock<[PipelineEvent]>

    public init() {
        _events = OSAllocatedUnfairLock(initialState: [])
    }

    public func record(_ event: PipelineEvent) {
        _events.withLock { $0.append(event) }
    }

    public var events: [PipelineEvent] {
        _events.withLock { $0 }
    }
}

// MARK: - Dependency container with grouped construction

public struct PipelineDependencies: Sendable {
    public let snapshotEngine: SnapshotEngineProtocol
    public let transcriber: TranscriberProtocol
    public let reasoner: ReasonerProtocol
    public let speech: SpeechSynthesizerProtocol
    public let clock: ClockProtocol
    public let micGate: MicSuppressionGate
    public let log: LogFunction
    public let playChime: @Sendable (ChimeType) -> Void
    public let eventRecorder: EventRecorder?

    public init(
        pipeline: PipelineComponents,
        speech: SpeechSynthesizerProtocol,
        feedback: FeedbackComponents,
        eventRecorder: EventRecorder? = nil
    ) {
        self.snapshotEngine = pipeline.snapshotEngine
        self.transcriber = pipeline.transcriber
        self.reasoner = pipeline.reasoner
        self.speech = speech
        self.clock = feedback.clock
        self.micGate = feedback.micGate
        self.log = feedback.log
        self.playChime = feedback.playChime
        self.eventRecorder = eventRecorder
    }
}

extension PipelineDependencies {
    public struct PipelineComponents: Sendable {
        public let snapshotEngine: SnapshotEngineProtocol
        public let transcriber: TranscriberProtocol
        public let reasoner: ReasonerProtocol

        public init(
            snapshotEngine: SnapshotEngineProtocol,
            transcriber: TranscriberProtocol,
            reasoner: ReasonerProtocol
        ) {
            self.snapshotEngine = snapshotEngine
            self.transcriber = transcriber
            self.reasoner = reasoner
        }
    }

    public struct FeedbackComponents: Sendable {
        public let clock: ClockProtocol
        public let micGate: MicSuppressionGate
        public let log: LogFunction
        public let playChime: @Sendable (ChimeType) -> Void

        public init(
            clock: ClockProtocol = SystemClock(),
            micGate: MicSuppressionGate = MicSuppressionGate(),
            log: @escaping LogFunction = { fputs($0, stderr) },
            playChime: @escaping @Sendable (ChimeType) -> Void = { AudioFeedback.play($0) }
        ) {
            self.clock = clock
            self.micGate = micGate
            self.log = log
            self.playChime = playChime
        }
    }
}

public final class LogCollector: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())

    public init() {}

    public func append(_ s: String) {
        lock.withLock { $0.append(s) }
    }

    public var logs: [String] {
        lock.withLock { $0 }
    }

    public func snapshot() -> [String] {
        lock.withLock { $0 }
    }
}

// MARK: - SnapshotEngineFake

public final class SnapshotEngineFake: SnapshotEngineProtocol, @unchecked Sendable {
    public var stubSnapshot: Result<Data?, Error> = .success(nil)
    public var stubCaptureTime: CMTime?
    public var ingestedPayloads: [AudioSamplePayload] = []

    public init() {}

    public func ingestPayload(_ payload: AudioSamplePayload) async {
        ingestedPayloads.append(payload)
    }

    public func snapshot(before timestamp: CMTime, duration: TimeInterval) async throws -> Data? {
        switch stubSnapshot {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    public func currentCaptureTime() async -> CMTime? {
        stubCaptureTime
    }
}

// MARK: - SpeechSynthesizerFake

public final class SpeechSynthesizerFake: SpeechSynthesizerProtocol, @unchecked Sendable {
    public var spokenTexts: [(String, String?)] = []
    public var delay: TimeInterval = 0
    public var shouldFail = false

    public init() {}

    public func speak(_ text: String, language: String?) async -> SpeechResult {
        if shouldFail { return .failed }
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return .cancelled
            }
        }
        spokenTexts.append((text, language))
        return .completed
    }

    public func stop() {}
}

// MARK: - TestSpeechDriver (injectable delegate seam)

public final class TestSpeechDriver: SpeechDriverProtocol, @unchecked Sendable {
    public weak var delegate: AVSpeechSynthesizerDelegate?
    public var capturedUtterance: AVSpeechUtterance?
    public var stopCallCount = 0

    public init() {}

    public func speak(_ utterance: AVSpeechUtterance) {
        capturedUtterance = utterance
    }

    @discardableResult
    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCallCount += 1
        return true
    }

    public func fireDidFinish() {
        delegate?.speechSynthesizer?(AVSpeechSynthesizer(), didFinish: AVSpeechUtterance(string: ""))
    }

    public func fireDidCancel() {
        delegate?.speechSynthesizer?(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: ""))
    }
}

// MARK: - ClockFake

public final class ClockFake: ClockProtocol, Sendable {
    private let _state: OSAllocatedUnfairLock<(now: TimeInterval, sleeps: [TimeInterval])>

    public init() {
        _state = OSAllocatedUnfairLock(initialState: (now: 0, sleeps: []))
    }

    public func now() -> TimeInterval {
        _state.withLock { $0.now }
    }

    public func advance(by: TimeInterval) {
        _state.withLock { $0.now += by }
    }

    public func sleep(seconds: TimeInterval) async throws {
        _state.withLock {
            $0.now += seconds
            $0.sleeps.append(seconds)
        }
    }

    public var sleeps: [TimeInterval] {
        _state.withLock { $0.sleeps }
    }

    public var totalSlept: TimeInterval {
        _state.withLock { $0.sleeps.reduce(0, +) }
    }
}
