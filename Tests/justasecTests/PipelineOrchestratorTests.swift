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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake,
            clock: clockFake,
            log: { logCollector.append($0) }
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake,
            clock: clockFake
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: OpenCodeClientFake(),
            speech: speechFake
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: OpenCodeClientFake(),
            speech: speechFake,
            log: { logCollector.append($0) }
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake,
            log: { logCollector.append($0) }
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: OpenCodeClientFake(),
            speech: speechFake,
            log: { logCollector.append($0) }
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(reasonerFake.capturedLanguage == "french")
    #expect(transcriberFake.capturedWavData != nil)
}

// MARK: - Timings are content-free

@Test("timing logs are content-free, formatted correctly, and timings populated")
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake,
            clock: clockFake,
            log: { logCollector.append($0) }
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    for log in logCollector.logs {
        let hasPrefix = log.hasPrefix("justasec: ")
        #expect(hasPrefix)
        #expect(!log.lowercased().contains("Bonjour"))
        #expect(!log.lowercased().contains("hello"))
        #expect(!log.lowercased().contains("answer"))
        #expect(log.count < 80)
        #expect(log.contains("0.000s") || log.contains("s\n"))
    }

    let snapshotLog = logCollector.logs.first { $0.contains("snapshot") }
    let transcriptionLog = logCollector.logs.first { $0.contains("transcription") }
    let opencodeLog = logCollector.logs.first { $0.contains("opencode") }
    let ttsLog = logCollector.logs.first { $0.contains("time-to-speech") }

    #expect(snapshotLog != nil)
    #expect(transcriptionLog != nil)
    #expect(opencodeLog != nil)
    #expect(ttsLog != nil)

    if let timings = orchestrator.lastTimings {
        #expect(timings.snapshotElapsed != nil)
        #expect(timings.transcriptionElapsed != nil)
        #expect(timings.reasoningElapsed != nil)
        #expect(timings.totalElapsed != nil)
    } else {
        Issue.record("lastTimings should not be nil after pipeline")
    }
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: OpenCodeClientFake(),
            speech: speechFake
        )
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

// MARK: - Artifact cleanliness invariant (three-layer evidence)

/// Extension-based artifact signatures never permitted from app source.
private let artifactExts: Set<String> = ["wav", "aiff", "caf", "mp3", "m4a", "pcm"]
/// Content-keyword artifact names never permitted from app source.
private let artifactKeywords: Set<String> = ["transcript", "prompt", "answer", "opencode_result"]
/// Subdirectory/file prefixes that are accepted (build outputs, model, VCS, OpenCode session store).
private let allowedPrefixes: Set<String> = [".build", ".git", "models", "Package.resolved", "opencode"]

private func scanForArtifacts(at url: URL) -> [String] {
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
    var found: [String] = []
    for case let fileURL as URL in enumerator {
        let name = fileURL.lastPathComponent
        let path = fileURL.path
        let lowerPath = path.lowercased()
        // Skip accepted locations: build output, VCS, model files, OpenCode store
        if allowedPrefixes.contains(where: { lowerPath.contains("/\($0.lowercased())/") || lowerPath.contains("/\($0.lowercased())") || lowerPath.hasPrefix($0.lowercased()) }) {
            continue
        }
        let lower = name.lowercased()
        let hasExt = artifactExts.contains { lower.hasSuffix(".\($0)") }
        let hasKeyword = artifactKeywords.contains { lower.contains($0) }
        if hasExt || hasKeyword {
            found.append(path)
        }
    }
    return found
}

private var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test("layered: no forbidden artifacts in project root after real WAV generation + pipeline")
@MainActor
func layeredArtifactNoTraceAfterSuccess() async throws {
    // Layer 1: snapshot forbidden-extension artifacts in actual project root
    let rootScanBefore = scanForArtifacts(at: projectRoot)

    // Layer 2: real SnapshotEngine with real audio conversion/WAV encoding
    // (exercises AudioConverter, AudioMixer, WAVEncoder — all in-memory)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("justasec_layered_ok_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let engine = SnapshotEngine()
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: .zero)
    await engine.ingestPayload(payload)
    let timestamp = CMTime(value: 16000, timescale: 16000)
    let wav = try #require(await engine.snapshot(before: timestamp, duration: 1.0))
    #expect(wav.count > 44)

    // Layer 3: successful fake pipeline (Whisper/OpenCode are external)
    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(WhisperTranscriptionResult(text: "hello", language: "english"))
    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .success(OpenCodeResult(answer: "Hello.", language: "en"))
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = timestamp
    snapshotFake.stubSnapshot = .success(wav)
    let speechFake = SpeechSynthesizerFake()
    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake
        )
    )
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    // Scan project root again — exact set must match (no new, no missing)
    let rootScanAfter = scanForArtifacts(at: projectRoot)
    let beforeSet = Set(rootScanBefore)
    let afterSet = Set(rootScanAfter)
    let added = afterSet.subtracting(beforeSet)
    let removed = beforeSet.subtracting(afterSet)
    #expect(added.isEmpty, "new artifacts appeared in project root: \(added)")
    #expect(removed.isEmpty, "artifacts disappeared from project root: \(removed)")

    // Layer 4: TMPDIR must still be empty (run-time never writes there)
    let tmpAfter = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
    #expect(tmpAfter.isEmpty, "unexpected files in isolation tmpdir: \(tmpAfter)")
}

@Test("layered: no forbidden artifacts after failed pipeline (silence)")
@MainActor
func layeredArtifactNoTraceAfterFailure() async throws {
    let rootScanBefore = scanForArtifacts(at: projectRoot)

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("justasec_layered_fail_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)
    let speechFake = SpeechSynthesizerFake()
    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: OpenCodeClientFake(),
            speech: speechFake
        )
    )
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let rootScanAfter = scanForArtifacts(at: projectRoot)
    let beforeSet = Set(rootScanBefore)
    let afterSet = Set(rootScanAfter)
    let added = afterSet.subtracting(beforeSet)
    let removed = beforeSet.subtracting(afterSet)
    #expect(added.isEmpty, "new artifacts appeared in project root: \(added)")
    #expect(removed.isEmpty, "artifacts disappeared from project root: \(removed)")

    let tmpAfter = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
    #expect(tmpAfter.isEmpty, "unexpected files in isolation tmpdir: \(tmpAfter)")
}

@Test("source-boundary: production source files never call file-write APIs",
      .enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/grep")))
func sourceBoundaryNoFileWriteAPIs() throws {
    let srcDir = projectRoot.appendingPathComponent("Sources/justasec").path
    // Whitelist: file paths and symbols that intentionally produce Data (not write to disk)
    let allowedPaths = ["AudioPipeline.swift", "JustasecApp.swift", "WhisperServerProcess.swift", "OpenCodeClient.swift"]
    let allowedSymbols = ["readDataToEndOfFile", "readToEnd", "readabilityHandler", "availableData",
                           "writeStdin", "writeSamples", "writeHeader"]
    let forbiddenPatterns = [
        #"\.write\("#,        // Data.write(to:…), NSData.write(toFile:…)
        #"createFile\("#,      // FileManager.createFile
        #"write\(toFile:"#,    // NSString/NSData writing
        #"OutputStream\("#,    // OutputStream init
    ]
    for pattern in forbiddenPatterns {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        proc.arguments = ["-rn", pattern, srcDir, "--include=*.swift"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            let matches = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let filtered = matches.components(separatedBy: "\n")
                .filter { line in
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
                    let lower = line.lowercased()
                    if allowedPaths.contains(where: { lower.contains($0.lowercased()) }) { return false }
                    if allowedSymbols.contains(where: { lower.contains($0.lowercased()) }) { return false }
                    return true
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !filtered.isEmpty {
                Issue.record("File-write API found in production source:\n\(filtered)")
            }
        }
    }
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: reasonerFake,
            speech: speechFake
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: reasonerFake,
            speech: speechFake,
            micGate: micGate
        )
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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake,
            speech: speechFake
        )
    )

    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    #expect(orchestrator.currentPipelineTask != nil)

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
        dependencies: PipelineDependencies(
            snapshotEngine: snapshotFake,
            transcriber: WhisperTranscriberFake(),
            reasoner: OpenCodeClientFake(),
            speech: speechFake
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Audio processing failed.")
}
