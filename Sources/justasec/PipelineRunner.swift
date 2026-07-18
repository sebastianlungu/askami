import Foundation
import CoreMedia

public struct PipelineRunner: Sendable {
    public let snapshotEngine: SnapshotEngineProtocol
    public let transcriber: TranscriberProtocol
    public let reasoner: ReasonerProtocol
    public let clock: ClockProtocol
    public let log: LogFunction

    public init(dependencies: PipelineDependencies) {
        self.snapshotEngine = dependencies.snapshotEngine
        self.transcriber = dependencies.transcriber
        self.reasoner = dependencies.reasoner
        self.clock = dependencies.clock
        self.log = dependencies.log
    }

    public struct StageResult: Sendable {
        public let wavData: Data
        public let transcription: WhisperTranscriptionResult
        public let answer: OpenCodeResult
    }

    public struct StageTimings: Sendable {
        public var snapshotElapsed: TimeInterval = 0
        public var transcriptionElapsed: TimeInterval = 0
        public var reasoningElapsed: TimeInterval = 0
    }

    public func captureTime() async throws -> CMTime {
        guard let t = await snapshotEngine.currentCaptureTime() else {
            throw PipelineError.captureFailed("no capture time")
        }
        return t
    }

    public func snapshot(before time: CMTime, timings: inout StageTimings) async throws -> Data {
        let start = clock.now()
        guard let wav = try await snapshotEngine.snapshot(before: time, duration: 30.0) else {
            throw PipelineError.silence
        }
        timings.snapshotElapsed = clock.now() - start
        log("justasec: snapshot \(fmt(timings.snapshotElapsed))s\n")
        return wav
    }

    public func transcribe(wav: Data, timings: inout StageTimings) async throws -> WhisperTranscriptionResult {
        let start = clock.now()
        let r = try await transcriber.transcribe(wavData: wav, timeout: 30.0)
        timings.transcriptionElapsed = clock.now() - start
        log("justasec: transcription \(fmt(timings.transcriptionElapsed))s\n")
        return r
    }

    public func reason(_ t: WhisperTranscriptionResult, timings: inout StageTimings) async throws -> OpenCodeResult {
        let start = clock.now()
        let r = try await reasoner.analyze(transcript: t.text, language: t.language)
        timings.reasoningElapsed = clock.now() - start
        log("justasec: opencode \(fmt(timings.reasoningElapsed))s\n")
        return r
    }

    private func fmt(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }
}
