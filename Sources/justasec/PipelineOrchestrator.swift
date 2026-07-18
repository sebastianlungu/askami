import Foundation

@MainActor
public final class PipelineOrchestrator {
    public private(set) var stateMachine: LifecycleStateMachine
    public private(set) var lastTimings: TimingSnapshot?
    public private(set) var currentPipelineTask: Task<Void, Never>?

    private let deps: PipelineDependencies

    public init(
        stateMachine: LifecycleStateMachine = LifecycleStateMachine(),
        dependencies: PipelineDependencies
    ) {
        self.stateMachine = stateMachine
        self.deps = dependencies
    }

    public func handleTrigger() {
        guard stateMachine.canTrigger else {
            AudioFeedback.play(.busy)
            return
        }

        AudioFeedback.play(.trigger)
        stateMachine.trigger()

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
            let answer = try await runner.reason(transcription, timings: &timings)

            let elapsed = runner.clock.now() - startTime
            runner.log("justasec: time-to-speech \(String(format: "%.3f", elapsed))s\n")

            await self.speakOnMain(answer: answer, timings: timings, totalElapsed: elapsed)
        } catch let error as PipelineError where error == .silence {
            await self.speakOnMain(errorMessage: "No speech detected.", settle: 0.3)
        } catch {
            let elapsed = runner.clock.now() - startTime
            await self.speakOnMain(pipelineError: error, totalElapsed: elapsed)
        }
    }

    nonisolated private func speakOnMain(
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
            try await MainActor.run { [self] in
                try stateMachine.beginSpeaking()
                deps.micGate.startSuppression()
            }
            await deps.speech.speak(answer.answer, language: answer.language)
            await deps.micGate.endSuppression(after: 0.5)
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
                deps.micGate.startSuppression()
            }
            await deps.speech.speak(errorMessage, language: "en")
            await deps.micGate.endSuppression(after: settle)
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
            deps.log("justasec: \(logMsg) \(error)\n")
        }

        await speakOnMain(errorMessage: message, settle: 0.3)
    }
}
