import Testing
import CoreMedia
import Foundation
@testable import justasec

private func makeTestWAV() -> Data {
    let samples: [Float32] = [0.1, 0.2, 0.3, 0.4]
    return try! WAVEncoder.encodePCM16(samples, sampleRate: 16000)
}

@MainActor
private func runPipeline(_ orchestrator: PipelineOrchestrator) async {
    orchestrator.handleTrigger()
    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
}

// MARK: - Exact once

@Test("ready state trigger produces exactly one pipeline run and one spoken answer")
@MainActor
func readyTriggerExactOnce() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "What is the capital of France?", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "The capital of France is Paris.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    let logCollector = LogCollector()
    let clockFake = ClockFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake,
        clock: clockFake,
        log: { logCollector.append($0) }
    )

    try orchestrator.stateMachine.startupComplete()
    #expect(orchestrator.stateMachine.canTrigger)

    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "The capital of France is Paris.")
    #expect(speechFake.spokenTexts[0].1 == "en")
    #expect(transcriberFake.capturedWavData != nil)
    #expect(reasonerFake.capturedTranscript == "What is the capital of France?")
    #expect(reasonerFake.capturedLanguage == "english")
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - Busy trigger ignored

@Test("trigger while processing is ignored with busy chime")
@MainActor
func busyTriggerDuringProcessing() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hello.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.3

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    #expect(orchestrator.stateMachine.state == .processing)

    orchestrator.handleTrigger()
    #expect(orchestrator.stateMachine.state == .processing)

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }

    #expect(speechFake.spokenTexts.count == 1)
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - State transitions

@Test("state transitions processing to speaking to ready on success")
@MainActor
func stateTransitionsSuccess() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hi.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.05

    let clockFake = ClockFake()
    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake,
        clock: clockFake
    )

    try orchestrator.stateMachine.startupComplete()
    orchestrator.handleTrigger()
    #expect(orchestrator.stateMachine.state == .processing)

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - Silence produces error speech

@Test("silence snapshot produces error speech and no transcript")
@MainActor
func silenceProducesError() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)

    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: OpenCodeClientFake(),
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "No speech detected.")
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - Errors produce error speech

@Test("transcription error produces error speech")
@MainActor
func transcriptionErrorProducesSpeech() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .failure(.inferenceFailed("HTTP 500"))

    let speechFake = SpeechSynthesizerFake()
    let logCollector = LogCollector()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: OpenCodeClientFake(),
        speech: speechFake,
        log: { logCollector.append($0) }
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Transcription failed.")

    let hasErrorLog = logCollector.logs.contains { $0.contains("transcription error") }
    #expect(hasErrorLog)
}

@Test("opencode error produces error speech")
@MainActor
func openCodeErrorProducesSpeech() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .failure(.timeout)

    let speechFake = SpeechSynthesizerFake()
    let logCollector = LogCollector()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake,
        log: { logCollector.append($0) }
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Reasoning process failed.")
    let hasErrorLog = logCollector.logs.contains { $0.contains("opencode error") }
    #expect(hasErrorLog)
}

@Test("pipeline error produces error speech")
@MainActor
func pipelineErrorProducesSpeech() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .failure(
        AudioPipelineError.conversionFailed("test error")
    )

    let speechFake = SpeechSynthesizerFake()
    let logCollector = LogCollector()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: OpenCodeClientFake(),
        speech: speechFake,
        log: { logCollector.append($0) }
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Audio processing failed.")
}

// MARK: - Language pass-through

@Test("whisper language passes through to opencode")
@MainActor
func languagePassThrough() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "Bonjour le monde", language: "french")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Bonjour.", language: "fr")
    )

    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(reasonerFake.capturedLanguage == "french")
    #expect(transcriberFake.capturedWavData != nil)
}

// MARK: - Timings are content-free

@Test("timing logs are content-free and formatted correctly")
@MainActor
func timingLogsContentFree() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hi.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    let clockFake = ClockFake()
    clockFake.nowValue = 1000
    let logCollector = LogCollector()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake,
        clock: clockFake,
        log: { logCollector.append($0) }
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    for log in logCollector.logs {
        #expect(log.hasPrefix("justasec: "))
        #expect(!log.lowercased().contains("Bonjour"))
        #expect(!log.lowercased().contains("hello"))
        #expect(!log.lowercased().contains("answer"))
        #expect(log.count < 80)
    }

    let snapshotLog = logCollector.logs.first { $0.contains("snapshot") }
    let transcriptionLog = logCollector.logs.first { $0.contains("transcription") }
    let opencodeLog = logCollector.logs.first { $0.contains("opencode") }
    let ttsLog = logCollector.logs.first { $0.contains("time-to-speech") }

    #expect(snapshotLog != nil)
    #expect(transcriptionLog != nil)
    #expect(opencodeLog != nil)
    #expect(ttsLog != nil)
}

// MARK: - Capture continues during pipeline

@Test("capture continues ingesting payloads during pipeline")
@MainActor
func captureContinuesDuringPipeline() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hi.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.2

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()

    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let prePayload = AudioSamplePayload(
        data: Data([1]), timestamp: CMTime(value: 0, timescale: 48000),
        format: format, source: .microphone
    )
    await snapshotFake.ingestPayload(prePayload)

    orchestrator.handleTrigger()

    for i in 0..<3 {
        let payload = AudioSamplePayload(
            data: Data([UInt8(i)]),
            timestamp: CMTime(value: CMTimeValue(i * 100), timescale: 48000),
            format: format, source: .systemAudio
        )
        await snapshotFake.ingestPayload(payload)
    }

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }

    #expect(snapshotFake.ingestedPayloads.count >= 4)
    #expect(orchestrator.stateMachine.state == .ready)

    let postPayload = AudioSamplePayload(
        data: Data([5]), timestamp: CMTime(value: 500, timescale: 48000),
        format: format, source: .microphone
    )
    await snapshotFake.ingestPayload(postPayload)
    #expect(snapshotFake.ingestedPayloads.count >= 5)
}

// MARK: - No sensitive content in logs or errors

@Test("error speech does not contain sensitive content")
@MainActor
func errorSpeechNoContent() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)

    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: OpenCodeClientFake(),
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    let message = speechFake.spokenTexts[0].0
    #expect(!message.lowercased().contains("transcript"))
    #expect(!message.lowercased().contains("answer"))
    #expect(!message.lowercased().contains("hello"))
    #expect(message.count < 100)
}

// MARK: - No queue

@Test("triggers during speaking do not queue")
@MainActor
func noQueueDuringSpeaking() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hello world.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.3

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: reasonerFake,
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()

    for _ in 0..<5 {
        orchestrator.handleTrigger()
    }

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }

    #expect(speechFake.spokenTexts.count == 1)
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - Mic suppression integrated

@Test("orchestrator activates mic suppression during speaking")
@MainActor
func micSuppressionDuringSpeaking() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Test.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.1

    let micGate = MicSuppressionGate()
    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: reasonerFake,
        speech: speechFake,
        micGate: micGate
    )

    try orchestrator.stateMachine.startupComplete()
    #expect(!micGate.isSuppressing)

    await runPipeline(orchestrator)
    #expect(!micGate.isSuppressing)
}

// MARK: - Off-MainActor pipeline evidence

@Test("pipeline with Task.detached completes correctly")
@MainActor
func pipelineOffMainActor() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())

    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )

    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(
        OpenCodeResult(answer: "Hi.", language: "en")
    )

    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: transcriberFake,
        reasoner: reasonerFake,
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    #expect(orchestrator.currentPipelineTask != nil)
    let isDetached = orchestrator.currentPipelineTask?.isCancelled == false

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }

    #expect(orchestrator.stateMachine.state == .ready)
    #expect(speechFake.spokenTexts.count == 1)
    #expect(snapshotFake.ingestedPayloads.count >= 0)
}

// MARK: - Runtime capture failure

@Test("runtime capture failure produces error speech")
@MainActor
func runtimeCaptureFailure() async throws {
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = nil

    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        snapshotEngine: snapshotFake,
        transcriber: WhisperTranscriberFake(),
        reasoner: OpenCodeClientFake(),
        speech: speechFake
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Audio processing failed.")
}
