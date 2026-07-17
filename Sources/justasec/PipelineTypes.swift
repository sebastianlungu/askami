import Foundation
import CoreMedia
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

public protocol SpeechSynthesizerProtocol: AnyObject, Sendable {
    func speak(_ text: String, language: String?) async
    func stop()
}

public protocol ClockProtocol: Sendable {
    func now() -> TimeInterval
}

public struct SystemClock: ClockProtocol, Sendable {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
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

public final class LogCollector: @unchecked Sendable {
    public var logs: [String] = []
    public init() {}
    public func append(_ s: String) { logs.append(s) }
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

    public init() {}

    public func speak(_ text: String, language: String?) async {
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        spokenTexts.append((text, language))
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

public final class ClockFake: ClockProtocol, @unchecked Sendable {
    public var nowValue: TimeInterval = 0

    public init() {}

    public func now() -> TimeInterval { nowValue }

    public func advance(by: TimeInterval) { nowValue += by }
}
