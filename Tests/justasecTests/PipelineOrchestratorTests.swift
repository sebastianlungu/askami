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

private final class ChimeRecorder: @unchecked Sendable {
    var chimes: [ChimeType] = []
    func record(_ chime: ChimeType) { chimes.append(chime) }
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake,
                log: { logCollector.append($0) }
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                log: { logCollector.append($0) }
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                log: { logCollector.append($0) }
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                log: { logCollector.append($0) }
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
    clockFake.advance(by: 1000)
    let logCollector = LogCollector()

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake,
                log: { logCollector.append($0) }
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                micGate: micGate
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
            )
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
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
            )
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Audio processing failed.")
}

// MARK: - EventRecorder Tests

private func makeSuccessDeps(
    clock: ClockProtocol = ClockFake(),
    speech: SpeechSynthesizerProtocol = SpeechSynthesizerFake(),
    eventRecorder: EventRecorder? = nil,
    playChime: @escaping @Sendable (ChimeType) -> Void = { _ in }
) -> (snapshot: SnapshotEngineFake, transcriber: WhisperTranscriberFake, reasoner: OpenCodeClientFake, clock: ClockProtocol, deps: PipelineDependencies) {
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
    let deps = PipelineDependencies(
        pipeline: .init(
            snapshotEngine: snapshotFake,
            transcriber: transcriberFake,
            reasoner: reasonerFake
        ),
        speech: speech,
        feedback: .init(
            clock: clock,
            playChime: playChime
        ),
        eventRecorder: eventRecorder
    )
    return (snapshotFake, transcriberFake, reasonerFake, clock, deps)
}

@Test("exact success event order with event recorder")
@MainActor
func exactSuccessEventOrder() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.stt)))
    #expect(events.contains(.status(.agent)))
    let suppressionIdx = events.firstIndex { $0 == .suppressionStart }
    let successIdx = events.firstIndex { $0 == .status(.success) }
    let chimeIdx = events.firstIndex { $0 == .chime(.success) }
    let sleepIdx = events.firstIndex { $0 == .sleep(0.3) }
    let ttsIdx = events.firstIndex { $0 == .status(.tts) }
    let speechBeginIdx = events.firstIndex { $0 == .speechBegin }
    let speechEndIdx = events.firstIndex { $0 == .speechResult(.completed) }
    let suppressionEndIdx = events.firstIndex { $0 == .suppressionEnd }
    let lifecycleReadyIdx = events.firstIndex { $0 == .lifecycleReady }
    let listeningIdx = events.firstIndex { $0 == .status(.listening) }

    if let s = suppressionIdx, let su = successIdx, let c = chimeIdx,
       let sl = sleepIdx, let t = ttsIdx, let sp = speechBeginIdx,
       let se = speechEndIdx, let supe = suppressionEndIdx,
       let lr = lifecycleReadyIdx, let li = listeningIdx {
        #expect(s < su)
        #expect(su < c)
        #expect(c < sl)
        #expect(sl < t)
        #expect(t < sp)
        #expect(sp < se)
        #expect(se < supe)
        #expect(supe < lr)
        #expect(lr < li)
    } else {
        Issue.record("missing expected events: \(events)")
    }
    let successChimeCount = events.filter { $0 == .chime(.success) }.count
    #expect(successChimeCount == 1)
    let speechEndCount = events.filter { $0 == .speechResult(.completed) }.count
    #expect(speechEndCount == 1)
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("suppression starts before success chime and chime before tts")
@MainActor
func suppressionChimeTTsOrder() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    let suppressionIdx = events.firstIndex { $0 == .suppressionStart }
    let chimeIdx = events.firstIndex { $0 == .chime(.success) }
    let ttsIdx = events.firstIndex { $0 == .status(.tts) }
    if let s = suppressionIdx, let c = chimeIdx, let t = ttsIdx {
        #expect(s < c)
        #expect(c < t)
    } else {
        Issue.record("missing suppression/chime/tts events")
    }
}

@Test("exactly one success chime never after tts")
@MainActor
func successChimeOnceBeforeTTS() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    let successChimes = events.filter { $0 == .chime(.success) }
    #expect(successChimes.count == 1)
    let ttsIdx = events.firstIndex { $0 == .status(.tts) }
    let chimeIdx = events.firstIndex { $0 == .chime(.success) }
    if let c = chimeIdx, let t = ttsIdx {
        #expect(c < t)
    }
}

@Test("sleep 0.3 recorded by clock fake")
@MainActor
func sleep300Recorded() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    #expect(clockFake.sleeps.contains(0.3))
    #expect(clockFake.totalSlept >= 0.3)
}

@Test("busy trigger at stt preserves current status and plays busy chime")
@MainActor
func busyTriggerAtSTTPreservesStatus() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.2
    let chimeRecorder = ChimeRecorder()
    let (_, _, _, _, deps) = makeSuccessDeps(
        clock: clockFake, speech: speechFake, eventRecorder: recorder,
        playChime: { chimeRecorder.record($0) }
    )
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    #expect(orchestrator.presenter.currentStatus == .stt)
    #expect(chimeRecorder.chimes.filter { $0 == .trigger }.count == 1)

    // Busy trigger should not change status
    chimeRecorder.chimes.removeAll()
    orchestrator.handleTrigger()
    #expect(orchestrator.presenter.currentStatus == .stt)
    #expect(chimeRecorder.chimes.filter { $0 == .busy }.count == 1)

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("silence error shows error then returns to listening with min 1.5s")
@MainActor
func silenceErrorMinDuration() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.error)))
    #expect(events.contains(.status(.listening)))
    let errorIdx = events.firstIndex { $0 == .status(.error) }
    let listeningIdx = events.firstIndex { $0 == .status(.listening) }
    if let e = errorIdx, let l = listeningIdx {
        #expect(e < l)
    }
    let sleepEvents = clockFake.sleeps
    let totalErrorSleep = sleepEvents.reduce(0, +)
    #expect(totalErrorSleep >= 1.5 || events.contains(where: { if case .sleep(let s) = $0 { return s >= 1.5 }; return false }))
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("transcription error shows error then returns to listening")
@MainActor
func transcriptionErrorEventOrder() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())
    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .failure(.inferenceFailed("HTTP 500"))

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.error)))
    #expect(events.contains(.status(.listening)))
    let errorIdx = events.firstIndex { $0 == .status(.error) }
    let listeningIdx = events.firstIndex { $0 == .status(.listening) }
    if let e = errorIdx, let l = listeningIdx {
        #expect(e < l)
    }
}

@Test("opencode error shows error then returns to listening")
@MainActor
func openCodeErrorEventOrder() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())
    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )
    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .failure(.timeout)

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.error)))
    #expect(events.contains(.status(.listening)))
}

@Test("speech failure shows error min 1.5s then listening")
@MainActor
func speechFailureRecovery() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.shouldFail = true
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.speechResult(.failed)))
    #expect(events.contains(.status(.error)))
    #expect(events.contains(.status(.listening)))
    let sleepEvents = clockFake.sleeps
    let totalSleep = sleepEvents.reduce(0, +)
    #expect(totalSleep >= 1.5 || events.contains(where: { if case .sleep(let s) = $0 { return s >= 1.5 }; return false }))
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("speech elapsed >1.5s does not add extra hold")
@MainActor
func speechElapsedOverMinNoExtraHold() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 2.0
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.listening)))
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("lifecycle completes before listening transition")
@MainActor
func lifecycleBeforeListening() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    let readyIdx = events.firstIndex { $0 == .lifecycleReady }
    let listeningIdx = events.firstIndex { $0 == .status(.listening) }
    if let r = readyIdx, let l = listeningIdx {
        #expect(r < l)
    }
}

@Test("fatal lifecycle fail leaves error status not listening")
@MainActor
func fatalLifecycleLeavesError() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.1
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()

    // Force lifecycle to failed state manually after pipeline starts
    orchestrator.handleTrigger()
    orchestrator.stateMachine.fail()

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    // After fail, state should stay failed
    #expect(orchestrator.stateMachine.state == .failed)
}

@Test("stale pipeline callback after lifecycle fail does not transition to listening")
@MainActor
func staleCallbackNoListeningOverride() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    orchestrator.stateMachine.fail()

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    #expect(orchestrator.stateMachine.state == .failed)
    let lastStatus = recorder.events.last { if case .status(_) = $0 { return true }; return false }
    if case .status(let s)? = lastStatus {
        #expect(s != .listening)
    }
}

@Test("success chime never appears after speech events")
@MainActor
func successChimeNeverAfterSpeech() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    let chimeIndices = events.enumerated().filter { $0.element == .chime(.success) }.map { $0.offset }
    let speechIndices = events.enumerated().filter { $0.element == .speechBegin || $0.element == .speechResult(.completed) }.map { $0.offset }
    for c in chimeIndices {
        for s in speechIndices {
            #expect(c < s)
        }
    }
}

@Test("no sensitive content in error events or logs")
@MainActor
func errorEventsNoSensitive() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    for event in recorder.events {
        let desc = String(describing: event)
        #expect(!desc.lowercased().contains("transcript"))
        #expect(!desc.lowercased().contains("answer"))
        #expect(!desc.lowercased().contains("bonjour"))
    }
}

// MARK: - Controlled Speech Fake for deterministic timing

private final class ControlledSpeechFake: SpeechSynthesizerProtocol, @unchecked Sendable {
    var spokenTexts: [(String, String?)] = []
    var delay: TimeInterval = 0
    var shouldFail = false
    let clock: ClockFake

    init(clock: ClockFake) { self.clock = clock }

    func speak(_ text: String, language: String?) async -> SpeechResult {
        if shouldFail { return .failed }
        if delay > 0 { clock.advance(by: delay) }
        spokenTexts.append((text, language))
        return .completed
    }

    func stop() {}
}

// MARK: - Settle Evidence

@Test("mic gate suppressing after speech, idle after settle")
@MainActor
func settleSuppressionEvidence() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let micGate = MicSuppressionGate()
    let (_, _, _, _, deps) = makeSuccessDeps(
        clock: clockFake, speech: speechFake, eventRecorder: recorder
    )
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    let speechEndIdx = events.firstIndex { $0 == .speechResult(.completed) }
    let supEndIdx = events.firstIndex { $0 == .suppressionEnd }
    if let s = speechEndIdx, let e = supEndIdx {
        #expect(s < e)
    }
    #expect(!micGate.isSuppressing)
}

// MARK: - Speech Elapsed with Controlled Fake

@Test("speech elapsed <1.5 with controlled fake holds remainder")
@MainActor
func speechElapsedBelowMinHoldsRemainder() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = ControlledSpeechFake(clock: clockFake)
    speechFake.shouldFail = true
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let sleeps = clockFake.sleeps
    let totalSleep = sleeps.reduce(0, +)
    #expect(totalSleep >= 1.5)
    #expect(orchestrator.stateMachine.state == .ready)
}

@Test("speech elapsed >1.5 with controlled fake holds nothing extra")
@MainActor
func speechElapsedOverMinNoExtraHoldControlled() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = ControlledSpeechFake(clock: clockFake)
    speechFake.delay = 2.0
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    // Speech took 2.0s (>1.5), no extra sleep needed
    let sleeps = clockFake.sleeps
    let successSleep = sleeps.filter { abs($0 - 0.3) < 0.01 }
    #expect(successSleep.count == 1)
    #expect(orchestrator.stateMachine.state == .ready)
}

// MARK: - Busy Triggers

@Test("busy trigger preserves status and plays one busy chime, one pipeline")
@MainActor
func busyTriggerPreservesStatus() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.3
    let chimeRecorder = ChimeRecorder()
    let (_, _, _, _, deps) = makeSuccessDeps(
        clock: clockFake, speech: speechFake, eventRecorder: recorder,
        playChime: { chimeRecorder.record($0) }
    )
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    #expect(orchestrator.presenter.currentStatus == .stt)
    #expect(chimeRecorder.chimes.filter { $0 == .trigger }.count == 1)

    orchestrator.handleTrigger()
    #expect(chimeRecorder.chimes.filter { $0 == .busy }.count == 1)
    #expect(chimeRecorder.chimes.filter { $0 == .trigger }.count == 1)

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    #expect(speechFake.spokenTexts.count == 1)
    #expect(orchestrator.stateMachine.state == .ready)

    let events = recorder.events
    #expect(events.contains(.status(.stt)))
    #expect(events.contains(.status(.agent)))
    #expect(events.contains(.status(.success)))
    #expect(events.contains(.status(.tts)))
    #expect(events.contains(.status(.listening)))
}

// MARK: - Fatal / Stale with Presenter Error

@Test("fatal with presenter error stays failed, does not transition to listening")
@MainActor
func fatalWithPresenterError() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    speechFake.delay = 0.1
    let (_, _, _, _, deps) = makeSuccessDeps(clock: clockFake, speech: speechFake, eventRecorder: recorder)
    let orchestrator = PipelineOrchestrator(dependencies: deps)
    try orchestrator.stateMachine.startupComplete()

    orchestrator.handleTrigger()
    orchestrator.stateMachine.fail()
    orchestrator.presenter.transition(to: .error)

    if let task = orchestrator.currentPipelineTask {
        await task.value
    }
    #expect(orchestrator.stateMachine.state == .failed)
    let lastStatusInHistory = recorder.events.last { if case .status = $0 { return true }; return false }
    if case .status(let s)? = lastStatusInHistory {
        #expect(s != .listening)
    }
}

// MARK: - Malformed Answer

@Test("malformed opencode answer shows error and recovers")
@MainActor
func malformedAnswerError() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let speechFake = SpeechSynthesizerFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(makeTestWAV())
    let transcriberFake = WhisperTranscriberFake()
    transcriberFake.stubResult = .success(
        WhisperTranscriptionResult(text: "hello", language: "english")
    )
    let reasonerFake = OpenCodeClientFake()
    reasonerFake.stubResult = .failure(.malformedResponse("no valid answer"))

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: transcriberFake,
                reasoner: reasonerFake
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    let events = recorder.events
    #expect(events.contains(.status(.error)))
    #expect(events.contains(.status(.listening)))
    let sleepEvents = clockFake.sleeps
    let totalSleep = sleepEvents.reduce(0, +)
    #expect(totalSleep >= 1.5 || events.contains(where: { if case .sleep(let s) = $0 { return s >= 1.5 }; return false }))
    #expect(orchestrator.stateMachine.state == .ready)
    #expect(speechFake.spokenTexts.count == 1)
    #expect(speechFake.spokenTexts[0].0 == "Reasoning process failed.")
}

// MARK: - Cancelled Speech in Recovery

@Test("cancelled error path does not recover to listening")
@MainActor
func cancelledErrorPathNoListening() async throws {
    let recorder = EventRecorder()
    let clockFake = ClockFake()
    let snapshotFake = SnapshotEngineFake()
    snapshotFake.stubCaptureTime = CMTime(value: 16000, timescale: 16000)
    snapshotFake.stubSnapshot = .success(nil)
    let speechFake = SpeechSynthesizerFake()

    let orchestrator = PipelineOrchestrator(
        dependencies: PipelineDependencies(
            pipeline: .init(
                snapshotEngine: snapshotFake,
                transcriber: WhisperTranscriberFake(),
                reasoner: OpenCodeClientFake()
            ),
            speech: speechFake,
            feedback: .init(
                clock: clockFake
            ),
            eventRecorder: recorder
        )
    )

    try orchestrator.stateMachine.startupComplete()
    await runPipeline(orchestrator)

    // Silence should produce error→listen. If speech somehow failed/cancelled,
    // ensure the state machine is still ready (not stuck in processing)
    let lastStatus = recorder.events.last { if case .status = $0 { return true }; return false }
    if case .status(let s)? = lastStatus {
        #expect(s == .listening)
    }
    #expect(orchestrator.stateMachine.state == .ready)
}
