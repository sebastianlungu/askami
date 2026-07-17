import Foundation
import CoreMedia

public struct PipelineRunner: Sendable {
    public let snapshotEngine: SnapshotEngineProtocol
    public let transcriber: TranscriberProtocol
    public let reasoner: ReasonerProtocol
    public let clock: ClockProtocol
    public let log: LogFunction

    public init(
        snapshotEngine: SnapshotEngineProtocol,
        transcriber: TranscriberProtocol,
        reasoner: ReasonerProtocol,
        clock: ClockProtocol,
        log: @escaping LogFunction
    ) {
        self.snapshotEngine = snapshotEngine
        self.transcriber = transcriber
        self.reasoner = reasoner
        self.clock = clock
        self.log = log
    }

    public struct StageResult: Sendable {
        public let wavData: Data
        public let transcription: WhisperTranscriptionResult
        public let answer: OpenCodeResult
    }

    public func captureTime() async throws -> CMTime {
        guard let t = await snapshotEngine.currentCaptureTime() else {
            throw PipelineError.captureFailed("no capture time")
        }
        return t
    }

    public func snapshot(before time: CMTime) async throws -> Data {
        let start = clock.now()
        guard let wav = try await snapshotEngine.snapshot(
            before: time, duration: 30.0
        ) else {
            throw PipelineError.silence
        }
        log("justasec: snapshot \(fmt(clock.now() - start))s\n")
        return wav
    }

    public func transcribe(wav: Data) async throws -> WhisperTranscriptionResult {
        let start = clock.now()
        let r = try await transcriber.transcribe(wavData: wav, timeout: 30.0)
        log("justasec: transcription \(fmt(clock.now() - start))s\n")
        return r
    }

    public func reason(_ t: WhisperTranscriptionResult) async throws -> OpenCodeResult {
        let start = clock.now()
        let r = try await reasoner.analyze(transcript: t.text, language: t.language)
        log("justasec: opencode \(fmt(clock.now() - start))s\n")
        return r
    }

    private func fmt(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }
}
