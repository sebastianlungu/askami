import Foundation

@MainActor
public final class PipelineOrchestrator {
    public private(set) var stateMachine: LifecycleStateMachine
    public private(set) var lastTimings: TimingSnapshot?
    public private(set) var currentPipelineTask: Task<Void, Never>?

    private let snapshotEngine: SnapshotEngineProtocol
    private let transcriber: TranscriberProtocol
    private let reasoner: ReasonerProtocol
    private let speech: SpeechSynthesizerProtocol
    private let clock: ClockProtocol
    public let micGate: MicSuppressionGate
    private let log: LogFunction

    public init(
        stateMachine: LifecycleStateMachine = LifecycleStateMachine(),
        snapshotEngine: SnapshotEngineProtocol,
        transcriber: TranscriberProtocol,
        reasoner: ReasonerProtocol,
        speech: SpeechSynthesizerProtocol,
        clock: ClockProtocol = SystemClock(),
        micGate: MicSuppressionGate = MicSuppressionGate(),
        log: @escaping LogFunction = { fputs($0, stderr) }
    ) {
        self.stateMachine = stateMachine
        self.snapshotEngine = snapshotEngine
        self.transcriber = transcriber
        self.reasoner = reasoner
        self.speech = speech
        self.clock = clock
        self.micGate = micGate
        self.log = log
    }

    public func handleTrigger() {
        guard stateMachine.canTrigger else {
            AudioFeedback.play(.busy)
            return
        }

        AudioFeedback.play(.trigger)
        stateMachine.trigger()

        let runner = PipelineRunner(
            snapshotEngine: snapshotEngine,
            transcriber: transcriber,
            reasoner: reasoner,
            clock: clock,
            log: log
        )

        currentPipelineTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.runPipelineOffMain(runner: runner)
        }
    }

    nonisolated private func runPipelineOffMain(runner: PipelineRunner) async {
        let startTime = runner.clock.now()

        do {
            let captureTime = try await runner.captureTime()
            let wavData = try await runner.snapshot(before: captureTime)
            let transcription = try await runner.transcribe(wav: wavData)
            let answer = try await runner.reason(transcription)

            let elapsed = runner.clock.now() - startTime
            runner.log("justasec: time-to-speech \(String(format: "%.3f", elapsed))s\n")

            await self.speakOnMain(answer: answer, totalElapsed: elapsed)
        } catch let error as PipelineError where error == .silence {
            await self.speakOnMain(errorMessage: "No speech detected.", settle: 0.3)
        } catch {
            let elapsed = runner.clock.now() - startTime
            await self.speakOnMain(pipelineError: error, totalElapsed: elapsed)
        }
    }

    nonisolated private func speakOnMain(
        answer: OpenCodeResult, totalElapsed: TimeInterval
    ) async {
        await MainActor.run { [self] in
            lastTimings = TimingSnapshot(totalElapsed: totalElapsed)
        }
        do {
            try await MainActor.run { [self] in
                try stateMachine.beginSpeaking()
                micGate.startSuppression()
            }
            await speech.speak(answer.answer, language: answer.language)
            await micGate.endSuppression(after: 0.5)
            try await MainActor.run { [self] in
                try stateMachine.speakingComplete()
            }
        } catch {
            await MainActor.run { [self] in stateMachine.fail() }
        }
    }

    nonisolated private func speakOnMain(errorMessage: String, settle: TimeInterval) async {
        do {
            try await MainActor.run { [self] in
                try stateMachine.beginSpeaking()
                micGate.startSuppression()
            }
            await speech.speak(errorMessage, language: "en")
            await micGate.endSuppression(after: settle)
            try await MainActor.run { [self] in
                try stateMachine.speakingComplete()
            }
        } catch {
            await MainActor.run { [self] in stateMachine.fail() }
        }
    }

    nonisolated private func speakOnMain(pipelineError error: Error, totalElapsed: TimeInterval) async {
        let message: String
        let logMsg: String

        switch error {
        case is WhisperTranscriptionError:
            message = "Transcription failed."
            logMsg = "transcription error"
        case is OpenCodeError:
            message = "Reasoning process failed."
            logMsg = "opencode error"
        case is AudioPipelineError, is PipelineError:
            message = "Audio processing failed."
            logMsg = "pipeline error"
        default:
            message = "Something went wrong."
            logMsg = "unexpected error"
        }

        await MainActor.run { [self] in
            lastTimings = TimingSnapshot(totalElapsed: totalElapsed)
            log("justasec: \(logMsg) \(error)\n")
        }

        await speakOnMain(errorMessage: message, settle: 0.3)
    }
}
