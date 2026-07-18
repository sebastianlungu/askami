import Foundation

@MainActor
public final class PipelineOrchestrator {
    public private(set) var stateMachine: LifecycleStateMachine
    public private(set) var lastTimings: TimingSnapshot?
    public private(set) var currentPipelineTask: Task<Void, Never>?

    public let presenter: DockStatusPresenter
    private let deps: PipelineDependencies

    public init(
        stateMachine: LifecycleStateMachine = LifecycleStateMachine(),
        dependencies: PipelineDependencies,
        presenter: DockStatusPresenter = DockStatusPresenter()
    ) {
        self.stateMachine = stateMachine
        self.deps = dependencies
        self.presenter = presenter
    }

    public func handleTrigger() {
        guard stateMachine.canTrigger else {
            deps.playChime(.busy)
            deps.eventRecorder?.record(.chime(.busy))
            return
        }

        deps.playChime(.trigger)
        deps.eventRecorder?.record(.chime(.trigger))
        stateMachine.trigger()
        presenter.transition(to: .stt)
        deps.eventRecorder?.record(.status(.stt))

        let runner = PipelineRunner(dependencies: deps)

        currentPipelineTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.runPipelineOffMain(runner: runner)
        }
    }

    nonisolated private func runPipelineOffMain(runner: PipelineRunner) async {
        let startTime = runner.clock.now()
        var timings = PipelineRunner.StageTimings()

        do {
            let captureTime = try await runner.captureTime()
            let wavData = try await runner.snapshot(before: captureTime, timings: &timings)
            let transcription = try await runner.transcribe(wav: wavData, timings: &timings)

            await MainActor.run { [self] in
                presenter.transition(to: .agent)
                deps.eventRecorder?.record(.status(.agent))
            }
            let answer = try await runner.reason(transcription, timings: &timings)

            let elapsed = runner.clock.now() - startTime
            runner.log("justasec: time-to-speech \(String(format: "%.3f", elapsed))s\n")

            await self.speakOnMainWithFeedback(answer: answer, timings: timings, totalElapsed: elapsed)
        } catch let error as PipelineError where error == .silence {
            await self.speakOnMainWithRecovery(errorMessage: "No speech detected.", settle: 0.3)
        } catch {
            let elapsed = runner.clock.now() - startTime
            await self.speakOnMain(error: error, totalElapsed: elapsed)
        }
    }

    nonisolated private func speakOnMainWithFeedback(
        answer: OpenCodeResult, timings: PipelineRunner.StageTimings, totalElapsed: TimeInterval
    ) async {
        await MainActor.run { [self] in
            lastTimings = TimingSnapshot(
                snapshotElapsed: timings.snapshotElapsed,
                transcriptionElapsed: timings.transcriptionElapsed,
                reasoningElapsed: timings.reasoningElapsed,
                totalElapsed: totalElapsed
            )
        }
        do {
            try await beginSuccessFeedback()
            let result = await speakAnswer(answer)
            try await handleAnswerSpeech(result, answer: answer)
        } catch {
            await releaseAndFail()
        }
    }

    nonisolated private func beginSuccessFeedback() async throws {
        try await MainActor.run { [self] in
            try stateMachine.beginSpeaking()
            deps.micGate.startSuppression()
            deps.eventRecorder?.record(.suppressionStart)
            presenter.transition(to: .success)
            deps.eventRecorder?.record(.status(.success))
        }
        deps.playChime(.success)
        deps.eventRecorder?.record(.chime(.success))
        try await deps.clock.sleep(seconds: 0.3)
        deps.eventRecorder?.record(.sleep(0.3))
        await MainActor.run { [self] in
            presenter.transition(to: .tts)
            deps.eventRecorder?.record(.status(.tts))
        }
    }

    nonisolated private func speakAnswer(_ answer: OpenCodeResult) async -> SpeechResult {
        deps.eventRecorder?.record(.speechBegin)
        let result = await deps.speech.speak(answer.answer, language: answer.language)
        deps.eventRecorder?.record(.speechResult(result))
        return result
    }

    nonisolated private func handleAnswerSpeech(_ result: SpeechResult, answer: OpenCodeResult) async throws {
        switch result {
        case .completed:
            try await settleAndComplete()
        case .cancelled:
            await releaseSuppression(0)
            await MainActor.run { [self] in stateMachine.fail() }
        case .failed:
            try await recoverFromSpeechFailure()
        }
    }

    nonisolated private func recoverFromSpeechFailure() async throws {
        let errorStart = deps.clock.now()
        await MainActor.run { [self] in
            presenter.transition(to: .error)
            deps.eventRecorder?.record(.status(.error))
        }
        let errorResult = await deps.speech.speak("Speaking failed.", language: "en")
        deps.eventRecorder?.record(.speechResult(errorResult))
        try await holdMinVisible(from: errorStart)
        await releaseSuppression(0)
        try await completeLifecycleAndListen()
    }

    nonisolated private func settleAndComplete() async throws {
        await deps.micGate.endSuppression(after: 0.5)
        deps.eventRecorder?.record(.suppressionEnd)
        try await completeLifecycleAndListen()
    }

    nonisolated private func holdMinVisible(from start: TimeInterval) async throws {
        let elapsed = deps.clock.now() - start
        let minVisible: TimeInterval = 1.5
        if elapsed < minVisible {
            try await deps.clock.sleep(seconds: minVisible - elapsed)
            deps.eventRecorder?.record(.sleep(minVisible - elapsed))
        }
    }

    nonisolated private func completeLifecycleAndListen() async throws {
        try await MainActor.run { [self] in
            try stateMachine.speakingComplete()
            deps.eventRecorder?.record(.lifecycleReady)
            presenter.transition(to: .listening)
            deps.eventRecorder?.record(.status(.listening))
        }
    }

    nonisolated private func releaseSuppression(_ settle: TimeInterval) async {
        await deps.micGate.endSuppression(after: settle)
        deps.eventRecorder?.record(.suppressionEnd)
    }

    nonisolated private func releaseAndFail() async {
        await deps.micGate.endSuppression(after: 0)
        deps.eventRecorder?.record(.suppressionEnd)
        await MainActor.run { [self] in stateMachine.fail() }
    }

    nonisolated private func speakOnMainWithRecovery(errorMessage: String, settle: TimeInterval) async {
        let errorStart = deps.clock.now()
        do {
            try await MainActor.run { [self] in
                try stateMachine.beginSpeaking()
                deps.micGate.startSuppression()
                deps.eventRecorder?.record(.suppressionStart)
                presenter.transition(to: .error)
                deps.eventRecorder?.record(.status(.error))
            }
            let result = await attemptErrorSpeech(errorMessage)
            try await handleRecoverySpeech(result, errorStart: errorStart, settle: settle)
        } catch {
            await releaseAndFail()
        }
    }

    nonisolated private func attemptErrorSpeech(_ message: String) async -> SpeechResult {
        deps.eventRecorder?.record(.speechBegin)
        let result = await deps.speech.speak(message, language: "en")
        deps.eventRecorder?.record(.speechResult(result))
        return result
    }

    nonisolated private func handleRecoverySpeech(_ result: SpeechResult, errorStart: TimeInterval, settle: TimeInterval) async throws {
        switch result {
        case .completed, .failed:
            try await holdMinVisible(from: errorStart)
            await releaseSuppression(settle)
            try await completeLifecycleAndListen()
        case .cancelled:
            await releaseSuppression(0)
            await MainActor.run { [self] in stateMachine.fail() }
        }
    }

    nonisolated private func speakOnMain(error: Error, totalElapsed: TimeInterval) async {
        let (message, logMsg) = classifyError(error)
        await MainActor.run { [self] in
            lastTimings = TimingSnapshot(totalElapsed: totalElapsed)
            deps.log("justasec: \(logMsg) \(error)\n")
        }
        await speakOnMainWithRecovery(errorMessage: message, settle: 0.3)
    }

    nonisolated private func classifyError(_ error: Error) -> (String, String) {
        switch error {
        case is WhisperTranscriptionError:
            return ("Transcription failed.", "transcription error")
        case is OpenCodeError:
            return ("Reasoning process failed.", "opencode error")
        case is AudioPipelineError, is PipelineError:
            return ("Audio processing failed.", "pipeline error")
        default:
            return ("Something went wrong.", "unexpected error")
        }
    }
}
