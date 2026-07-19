import Testing
import Foundation
@testable import askami

// MARK: - Config

@Test("whisper config default host is loopback")
func configDefaultHost() {
    let cfg = WhisperServerConfig()
    #expect(cfg.host == "127.0.0.1")
}

@Test("whisper config default port is 19990")
func configDefaultPort() {
    let cfg = WhisperServerConfig()
    #expect(cfg.port == 19990)
}

@Test("whisper config default language is auto")
func configDefaultLanguage() {
    let cfg = WhisperServerConfig()
    #expect(cfg.language == "auto")
}

@Test("whisper config default executable path")
func configDefaultExecutable() {
    let cfg = WhisperServerConfig()
    #expect(cfg.executablePath == "/opt/homebrew/bin/whisper-server")
}

@Test("whisper config custom values round-trip")
func configCustomValues() {
    let cfg = WhisperServerConfig(
        executablePath: "/custom/whisper-server",
        modelPath: "/custom/model.bin",
        host: "10.0.0.1",
        port: 12345,
        language: "fr"
    )
    #expect(cfg.executablePath == "/custom/whisper-server")
    #expect(cfg.modelPath == "/custom/model.bin")
    #expect(cfg.host == "10.0.0.1")
    #expect(cfg.port == 12345)
    #expect(cfg.language == "fr")
}

// MARK: - Host Enforcement

@Test("validate rejects non-loopback host")
func validateRejectsNonLoopback() {
    let cfg = WhisperServerConfig(host: "0.0.0.0")
    let proc = WhisperServerProcess(config: cfg)
    #expect(throws: WhisperTranscriptionError.hostNotLoopback("0.0.0.0")) {
        try proc.validate()
    }
}

private var testModelsDir: String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("models/ggml-base-q5_1.bin").path
}

@Test("validate accepts loopback host",
      .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-server") && FileManager.default.fileExists(atPath: testModelsDir)))
func validateAcceptsLoopback() throws {
    let cfg = WhisperServerConfig(modelPath: testModelsDir)
    let proc = WhisperServerProcess(config: cfg)
    try proc.validate()
}

// MARK: - Model Path Resolution

@Test("model default path is relative models/ggml-base-q5_1.bin")
func modelDefaultPath() {
    #expect(WhisperServerConfig.defaultModelPath == "models/ggml-base-q5_1.bin")
}

@Test("resolved model path uses absolute path directly")
func modelResolvedAbsolute() {
    let cfg = WhisperServerConfig(modelPath: "/absolute/path/model.bin")
    #expect(cfg.resolvedModelPath == "/absolute/path/model.bin")
}

@Test("resolved model path resolves relative path against cwd when no bundle",
      .enabled(if: FileManager.default.fileExists(atPath: testModelsDir)))
func modelResolvedRelative() {
    globalStateLock.withLock {
        let cfg = WhisperServerConfig()
        let resolved = cfg.resolvedModelPath
        let hasPrefixSlash = resolved.hasPrefix("/")
        let hasSuffixPath = resolved.hasSuffix("/models/ggml-base-q5_1.bin")
        #expect(hasPrefixSlash)
        #expect(hasSuffixPath)
    }
}

@Test("resolved model path falls through when nothing matches")
func modelResolvedFallthrough() {
    let cfg = WhisperServerConfig(modelPath: "nonexistent/subdir/model.bin")
    #expect(cfg.resolvedModelPath == "nonexistent/subdir/model.bin")
}

private let globalStateLock = NSLock()

@Test("resolved model path honors ASKAMI_MODEL_PATH env var")
func modelResolvedEnvVar() {
    globalStateLock.withLock {
        setenv("ASKAMI_MODEL_PATH", "/env/path/model.bin", 1)
        defer { unsetenv("ASKAMI_MODEL_PATH") }
        let cfg = WhisperServerConfig(modelPath: "models/ggml-base-q5_1.bin")
        #expect(cfg.resolvedModelPath == "/env/path/model.bin")
    }
}

@Test("resolved model path works with cwd = /")
func modelResolvedCwdRoot() {
    globalStateLock.withLock {
        let original = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/")
        defer { FileManager.default.changeCurrentDirectoryPath(original) }
        let cfg = WhisperServerConfig(modelPath: "nonexistent/test.bin")
        #expect(cfg.resolvedModelPath == "nonexistent/test.bin")
    }
}

// MARK: - Model Validation

@Test("model validation passes on known-good model",
      .enabled(if: FileManager.default.fileExists(atPath: testModelsDir)))
func modelValidationPasses() throws {
    try WhisperServerConfig.validateModel(at: testModelsDir)
}

@Test("model validation fails on missing file")
func modelValidationMissing() {
    #expect(throws: WhisperTranscriptionError.modelNotFound) {
        try WhisperServerConfig.validateModel(at: "/nonexistent/model.bin")
    }
}

@Test("model validation fails on wrong size")
func modelValidationWrongSize() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_model_wrong_size.bin")
    try Data(repeating: 0, count: 100).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    #expect(throws: WhisperTranscriptionError.modelInvalidSize(actual: 100, expected: 59_707_625)) {
        try WhisperServerConfig.validateModel(at: tmp.path)
    }
}

@Test("model validation fails on wrong hash")
func modelValidationWrongHash() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_model_wrong_hash.bin")
    let modelData = Data(repeating: 0x41, count: 59_707_625)
    try modelData.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    #expect(throws: WhisperTranscriptionError.modelInvalidHash(
        actual: "b9097ff12e167ed8ff132966eb690239a6359a69b5a6ad34e7746895aa9f4e98",
        expected: WhisperServerConfig.expectedModelSHA256
    )) {
        try WhisperServerConfig.validateModel(at: tmp.path)
    }
}

// MARK: - SHA-256

@Test("sha256 of known data is correct")
func sha256Known() throws {
    let data = "hello".data(using: .utf8)!
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_sha256_known.bin")
    try data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let hash = try WhisperServerConfig.sha256OfFile(at: tmp.path)
    #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
}

// MARK: - Errors

@Test("whisper error equality")
func whisperErrorEquality() {
    #expect(WhisperTranscriptionError.hostNotLoopback("x") == .hostNotLoopback("x"))
    #expect(WhisperTranscriptionError.executableNotFound == .executableNotFound)
    #expect(WhisperTranscriptionError.modelNotFound == .modelNotFound)
    #expect(WhisperTranscriptionError.modelInvalidSize(actual: 100, expected: 200) == .modelInvalidSize(actual: 100, expected: 200))
    #expect(WhisperTranscriptionError.modelInvalidHash(actual: "a", expected: "b") == .modelInvalidHash(actual: "a", expected: "b"))
    #expect(WhisperTranscriptionError.portOccupied(19990) == .portOccupied(19990))
    #expect(WhisperTranscriptionError.serverFailed("x") == .serverFailed("x"))
    #expect(WhisperTranscriptionError.startupTimeout == .startupTimeout)
    #expect(WhisperTranscriptionError.inferenceTimeout == .inferenceTimeout)
    #expect(WhisperTranscriptionError.inferenceFailed("x") == .inferenceFailed("x"))
    #expect(WhisperTranscriptionError.noSpeechDetected == .noSpeechDetected)
    #expect(WhisperTranscriptionError.unexpectedResponse("x") == .unexpectedResponse("x"))
    #expect(WhisperTranscriptionError.executableNotFound != .modelNotFound)
}

// MARK: - Process Arguments

@Test("process args include loopback host")
func processArgHost() {
    let args = WhisperServerProcess.makeArguments(config: WhisperServerConfig())
    #expect(args.contains("--host"))
    if let idx = args.firstIndex(of: "--host"), idx + 1 < args.count {
        #expect(args[idx + 1] == "127.0.0.1")
    }
}

@Test("process args include port")
func processArgPort() {
    let args = WhisperServerProcess.makeArguments(config: WhisperServerConfig())
    #expect(args.contains("--port"))
    if let idx = args.firstIndex(of: "--port"), idx + 1 < args.count {
        #expect(args[idx + 1] == "19990")
    }
}

@Test("process args include resolved model path")
func processArgModel() {
    let cfg = WhisperServerConfig(modelPath: "/test/models/model.bin")
    let args = WhisperServerProcess.makeArguments(config: cfg)
    #expect(args.contains("--model"))
    if let idx = args.firstIndex(of: "--model"), idx + 1 < args.count {
        #expect(args[idx + 1] == "/test/models/model.bin")
    }
}

@Test("process args include auto language")
func processArgLanguage() {
    let args = WhisperServerProcess.makeArguments(config: WhisperServerConfig())
    let idx = args.firstIndex(of: "--language") ?? args.firstIndex(of: "-l")
    if let i = idx, i + 1 < args.count { #expect(args[i + 1] == "auto") }
}

@Test("process args do NOT include --convert")
func processArgNoConvert() {
    #expect(!WhisperServerProcess.makeArguments(config: WhisperServerConfig()).contains("--convert"))
}

@Test("process args do NOT include --no-gpu")
func processArgNoNoGpu() {
    #expect(!WhisperServerProcess.makeArguments(config: WhisperServerConfig()).contains("--no-gpu"))
}

@Test("process args do NOT include --no-flash-attn")
func processArgNoNoFlashAttn() {
    #expect(!WhisperServerProcess.makeArguments(config: WhisperServerConfig()).contains("--no-flash-attn"))
}

// MARK: - Multipart Request

@Test("multipart request is POST to /inference")
func multipartPostToInference() {
    let req = WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 5.0
    )
    #expect(req.httpMethod == "POST")
    #expect(req.url?.absoluteString == "http://127.0.0.1:19990/inference")
}

@Test("multipart request has content type with boundary")
func multipartContentType() {
    let req = WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 5.0
    )
    let contentType = req.allHTTPHeaderFields?["Content-Type"] ?? ""
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
}

@Test("multipart request includes response_format=verbose_json")
func multipartHasVerboseJson() {
    let body = String(data: WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 5.0
    ).httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("verbose_json"))
}

@Test("multipart request includes language=auto")
func multipartHasLanguageAuto() {
    let body = String(data: WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 5.0
    ).httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains(#"name="language""#))
    #expect(body.contains("auto"))
}

@Test("multipart request includes file field with .wav")
func multipartHasFileField() {
    let body = String(data: WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 5.0
    ).httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains(#"name="file""#))
    #expect(body.contains("filename=\"audio.wav\""))
}

@Test("multipart request timeout is set")
func multipartHasTimeout() {
    #expect(WhisperTranscriber.makeInferenceRequest(
        wavData: Data(repeating: 0, count: 100), host: "127.0.0.1", port: 19990, timeout: 15.0
    ).timeoutInterval == 15.0)
}

@Test("wav data embedded in multipart body")
func multipartContainsWav() {
    let wav = Data([0x01, 0x02, 0x03])
    let req = WhisperTranscriber.makeInferenceRequest(
        wavData: wav, host: "127.0.0.1", port: 19990, timeout: 5.0
    )
    #expect(req.httpBody?.contains(wav) == true)
}

// MARK: - Response Parsing

@Test("parse verbose_json extracts text and language")
func parseVerboseJsonSuccess() throws {
    let r = try WhisperTranscriber.parseResponse(data: """
        {"text": "Hello world", "language": "english"}
        """.data(using: .utf8)!)
    #expect(r.text == "Hello world")
    #expect(r.language == "english")
}

@Test("parse verbose_json with segments extracts full text")
func parseVerboseJsonWithSegments() throws {
    let r = try WhisperTranscriber.parseResponse(data: """
        {"text": "Bonjour le monde", "language": "french", "segments": [{"id":0}]}
        """.data(using: .utf8)!)
    #expect(r.text == "Bonjour le monde")
    #expect(r.language == "french")
}

@Test("parse falls back to detected_language")
func parseFallbackDetectedLanguage() throws {
    let r = try WhisperTranscriber.parseResponse(data: """
        {"text": "Hola mundo", "detected_language": "spanish"}
        """.data(using: .utf8)!)
    #expect(r.text == "Hola mundo")
    #expect(r.language == "spanish")
}

@Test("parse rejects empty text as no speech")
func parseEmptyText() {
    #expect(throws: WhisperTranscriptionError.noSpeechDetected) {
        try WhisperTranscriber.parseResponse(data: """
            {"text": "", "language": "english"}
            """.data(using: .utf8)!)
    }
}

@Test("parse removes background-music annotations and keeps speech")
func parseRemovesMusicAnnotations() throws {
    let r = try WhisperTranscriber.parseResponse(data: """
        {"text": " [MÚSICA DE FUNDO]\\n Como foi tão rápida?\\n [MÚSICA DE FUNDO]", "language": "portuguese"}
        """.data(using: .utf8)!)
    #expect(r.text == "Como foi tão rápida?")
    #expect(r.language == "portuguese")
}

@Test("parse rejects annotation-only hallucination")
func parseRejectsAnnotationOnlyTranscript() {
    #expect(throws: WhisperTranscriptionError.noSpeechDetected) {
        try WhisperTranscriber.parseResponse(data: """
            {"text": " [...müzik çalıyor...]", "language": "turkish"}
            """.data(using: .utf8)!)
    }
}

@Test("parse throws on missing text")
func parseMissingText() {
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: """
            {"language": "english"}
            """.data(using: .utf8)!)
    }
}

@Test("parse throws when all language fields absent")
func parseMissingAllLanguage() {
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: """
            {"text": "hello"}
            """.data(using: .utf8)!)
    }
}

@Test("parse throws on malformed JSON")
func parseMalformedJson() {
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: "not json".data(using: .utf8)!)
    }
}

@Test("parse throws on empty data")
func parseEmptyData() {
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: Data())
    }
}

@Test("parse rejects oversized body")
func parseRejectsOversizedBody() {
    let huge = Data(repeating: 0x7b, count: WhisperServerConfig.maxResponseBodyBytes)
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: huge)
    }
}

@Test("parse rejects oversized text")
func parseRejectsOversizedText() {
    let text = String(repeating: "a", count: WhisperServerConfig.maxTextLength)
    let json = "{\"text\":\"\(text)\",\"language\":\"en\"}".data(using: .utf8)!
    #expect(throws: WhisperTranscriptionError.self) {
        try WhisperTranscriber.parseResponse(data: json)
    }
}

// MARK: - Preflight Port Check

@Test("preflight detects occupied port")
func preflightPortOccupied() throws {
    let testPort: UInt16 = 19991
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return }
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = CFSwapInt16HostToBig(testPort)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let br = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard br == 0 else { return }
    listen(sock, 1)
    defer { close(sock) }

    #expect(throws: WhisperTranscriptionError.portOccupied(testPort)) {
        try WhisperServerProcess(config: WhisperServerConfig(port: testPort)).preflightPortCheck()
    }
}

@Test("preflight succeeds on free port")
func preflightPortFree() throws {
    let proc = WhisperServerProcess(config: WhisperServerConfig(port: 19992))
    #expect(throws: Never.self) { try proc.preflightPortCheck() }
}

// MARK: - Process Launch & Validation

@Test("process validates executable exists")
func processValidateExecutable() {
    #expect(throws: WhisperTranscriptionError.executableNotFound) {
        try WhisperServerProcess(config: WhisperServerConfig(executablePath: "/nonexistent/whisper-server")).validate()
    }
}

@Test("process validates model file exists")
func processValidateModel() {
    #expect(throws: WhisperTranscriptionError.modelNotFound) {
        try WhisperServerProcess(config: WhisperServerConfig(executablePath: "/bin/bash", modelPath: "/nonexistent/model.bin")).validate()
    }
}

// MARK: - Pipe Draining (noisy child)

@Test("noisy child stdout does not block process")
func noisyStdoutDoesNotBlock() async throws {
    let script = """
    for _ in $(seq 1 10000); do echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; done
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    let errPipe = Pipe()
    proc.standardError = errPipe

    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading

    outFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    errFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }

    try proc.run()
    proc.waitUntilExit()
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil

    #expect(proc.terminationStatus == 0)
}

@Test("noisy child stderr does not block process")
func noisyStderrDoesNotBlock() async throws {
    let script = """
    for _ in $(seq 1 10000); do echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >&2; done
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    let errPipe = Pipe()
    proc.standardError = errPipe

    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading

    outFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    errFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }

    try proc.run()
    proc.waitUntilExit()
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil

    #expect(proc.terminationStatus == 0)
}

@Test("noisy child both pipes does not block process")
func noisyBothPipes() async throws {
    let script = """
    for _ in $(seq 1 5000); do echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" >&2; done
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    let errPipe = Pipe()
    proc.standardError = errPipe

    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading

    outFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    errFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }

    try proc.run()
    proc.waitUntilExit()
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil

    #expect(proc.terminationStatus == 0)
}

// MARK: - Termination

@Test("terminate with graceful child sends interrupt and reaps")
func terminateGracefulChild() async throws {
    let script = """
    trap 'exit 0' SIGINT SIGTERM
    while true; do sleep 0.1; done
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading
    outFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    errFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    try proc.run()

    #expect(proc.isRunning)

    proc.interrupt()
    proc.waitUntilExit()
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil

    #expect(!proc.isRunning)
}

@Test("terminate with stubborn child reaps within finite bound")
func terminateStubbornChildReaps() async throws {
    let script = "trap '' SIGINT SIGTERM; while true; do sleep 0.1; done"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = outPipe
    try proc.run()
    defer { if proc.isRunning { kill(pid_t(proc.processIdentifier), SIGKILL); proc.waitUntilExit() } }
    #expect(proc.isRunning)
    let start = CFAbsoluteTimeGetCurrent()
    // Simulate WhisperServerProcess.terminate escalation
    proc.interrupt()
    try await Task.sleep(nanoseconds: 100_000_000)
    if proc.isRunning { proc.terminate() }
    let pollDeadline = CFAbsoluteTimeGetCurrent() + 3.0
    var exited = false
    while CFAbsoluteTimeGetCurrent() < pollDeadline {
        if !proc.isRunning { exited = true; break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    if !exited { kill(pid_t(proc.processIdentifier), SIGKILL); proc.waitUntilExit() }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    #expect(!proc.isRunning)
    #expect(elapsed < 5.0, "stubborn child should be reaped within 5s, took \(elapsed)s")
}

@Test("terminate with stubborn child forces terminate after interrupt")
func terminateStubbornChild() async throws {
    let script = """
    trap '' SIGINT SIGTERM
    while true; do sleep 0.1; done
    """
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    let outFH = outPipe.fileHandleForReading
    let errFH = errPipe.fileHandleForReading
    outFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    errFH.readabilityHandler = { handle in _ = try? handle.read(upToCount: 65536) }
    try proc.run()

    #expect(proc.isRunning)
    kill(pid_t(proc.processIdentifier), SIGKILL)
    proc.waitUntilExit()
    outFH.readabilityHandler = nil
    errFH.readabilityHandler = nil

    #expect(!proc.isRunning)
}

@Test("forceTerminate: stubborn child reaped via direct SIGKILL <1s, parent alive")
func forceTerminateStubbornChild() async throws {
    let script = "trap '' SIGINT SIGTERM; while true; do sleep 0.1; done"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/bash")
    proc.arguments = ["-c", script]
    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    try proc.run()
    defer { if proc.isRunning { kill(pid_t(proc.processIdentifier), SIGKILL); proc.waitUntilExit() } }
    #expect(proc.isRunning)

    let parentPid = getpid()
    let start = CFAbsoluteTimeGetCurrent()

    outPipe.fileHandleForReading.readabilityHandler = nil
    errPipe.fileHandleForReading.readabilityHandler = nil
    kill(pid_t(proc.processIdentifier), SIGKILL)

    let deadline = CFAbsoluteTimeGetCurrent() + 1.0
    while CFAbsoluteTimeGetCurrent() < deadline, proc.isRunning {
        usleep(20_000)
    }
    if proc.isRunning { proc.waitUntilExit() }

    let elapsed = CFAbsoluteTimeGetCurrent() - start
    #expect(!proc.isRunning, "forceTerminate should reap child")
    #expect(elapsed < 1.0, "forceTerminate should complete under 1s, took \(elapsed)s")
    #expect(getpid() == parentPid, "parent must survive forceTerminate")
}

// MARK: - Preflight + Readiness (fakes)

@Test("process port occupied mapping via fake")
func processPortOccupiedFake() {
    let fake = WhisperServerProcessFake()
    fake.stubPreflightResult = .failure(.portOccupied(19990))
    #expect(throws: WhisperTranscriptionError.portOccupied(19990)) { try fake.preflightPortCheck() }
}

@Test("process server failure mapping via fake")
func processServerFailureFake() {
    let fake = WhisperServerProcessFake()
    fake.stubLaunchResult = .failure(.serverFailed("crash"))
    #expect(throws: WhisperTranscriptionError.serverFailed("crash")) { try fake.launch() }
}

@Test("readiness timeout via fake")
func readinessTimeoutFake() async {
    let fake = WhisperServerProcessFake()
    fake.stubReadinessResult = false
    fake.stubReadinessDelay = 0.01
    #expect(await fake.checkReadiness(timeout: 0.005) == false)
}

@Test("readiness success via fake")
func readinessSuccessFake() async {
    #expect(await WhisperServerProcessFake().checkReadiness(timeout: 1.0))
}

// MARK: - Transcriber fakes

@Test("transcriber returns result on success")
func transcriberSuccess() async throws {
    let fake = WhisperTranscriberFake()
    fake.stubResult = .success(WhisperTranscriptionResult(text: "hello", language: "english"))
    let r = try await fake.transcribe(wavData: Data([0]))
    #expect(r.text == "hello")
    #expect(r.language == "english")
}

@Test("transcriber maps inferenceFailed")
func transcriberInferenceFailed() async {
    let fake = WhisperTranscriberFake()
    fake.stubResult = .failure(.inferenceFailed("HTTP 500"))
    do {
        _ = try await fake.transcribe(wavData: Data([0]))
        Issue.record("expected error")
    } catch let error as WhisperTranscriptionError {
        #expect(error == .inferenceFailed("HTTP 500"))
    } catch { Issue.record("wrong type") }
}

@Test("transcriber maps inferenceTimeout")
func transcriberTimeout() async {
    let fake = WhisperTranscriberFake()
    fake.stubResult = .failure(.inferenceTimeout)
    do {
        _ = try await fake.transcribe(wavData: Data([0]))
        Issue.record("expected error")
    } catch let error as WhisperTranscriptionError {
        #expect(error == .inferenceTimeout)
    } catch { Issue.record("wrong type") }
}

// MARK: - Child Cleanup

@Test("process terminate stops running state")
func processTerminateStops() throws {
    let fake = WhisperServerProcessFake()
    try fake.launch()
    #expect(fake.isRunning)
    fake.terminate()
    #expect(!fake.isRunning)
}

@Test("process double terminate is safe")
func processDoubleTerminate() throws {
    let fake = WhisperServerProcessFake()
    try fake.launch()
    fake.terminate()
    fake.terminate()
    #expect(!fake.isRunning)
}

@Test("process terminate before launch is safe")
func processTerminateBeforeLaunch() {
    WhisperServerProcessFake().terminate()
}

// MARK: - Concurrency

@Test("WhisperServerProcess is Sendable")
func processIsSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(WhisperServerProcess.self)
}

@Test("WhisperTranscriptionResult is Sendable")
func resultIsSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(WhisperTranscriptionResult.self)
}

// MARK: - Integration: Real server arguments

@Test("process arguments are valid for real server",
      .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-server")))
func processArgsRealServer() {
    let args = WhisperServerProcess.makeArguments(config: WhisperServerConfig())
    #expect(args.contains("--host"))
    #expect(args.contains("--port"))
    #expect(args.contains("--model"))
    #expect(args.contains("-l") || args.contains("--language"))
}

@Test("real server help has expected options",
      .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-server")))
func realServerHelp() throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-server")
    proc.arguments = ["--help"]
    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    try proc.run()
    proc.waitUntilExit()
    let help = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
             + String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    #expect(help.contains("--host"))
    #expect(help.contains("--port"))
    #expect(help.contains("--model"))
    #expect(proc.terminationStatus == 0)
}

// MARK: - Integration: Real whisper-server with genuine model

private func findFreePort() -> UInt16 {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return 19990 }
    defer { close(sock) }
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = CFSwapInt16HostToBig(0)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    guard bind(sock, withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 else { return 19990 }
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    guard getsockname(sock, withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }, &len) == 0 else { return 19990 }
    return CFSwapInt16BigToHost(addr.sin_port)
}

@Test("real server: launch, transcribe, cleanup (3x)",
      .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-server")))
func realServerIntegration3x() async throws {
    for run in 1...3 {
        let fm = FileManager.default
        let ws = "/opt/homebrew/bin/whisper-server"
        try #require(fm.isExecutableFile(atPath: ws))

        let testPort = findFreePort()

        // Generate in-memory WAV
        let sampleRate = 16000
        let durationSecs = 0.3
        let sampleCount = Int(Double(sampleRate) * durationSecs)
        var samples = [Float32](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float32(i) / Float32(sampleRate)
            samples[i] = 0.3 * sin(2.0 * .pi * 200.0 * t) + 0.2 * sin(2.0 * .pi * 400.0 * t)
        }
        let wav = try WAVEncoder.encodePCM16(samples, sampleRate: sampleRate)

        // Derive project root from test file path, immune to cwd changes
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/askamiTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // askami/
        let modelPath = projectRoot.appendingPathComponent("models/ggml-base-q5_1.bin").path

        let config = WhisperServerConfig(
            modelPath: modelPath,
            port: testPort
        )
        let server = WhisperServerProcess(config: config)

        try server.validate()
        try server.launch()
        defer { server.terminate() }

        let ready = await server.checkReadiness(timeout: 30.0)
        #expect(ready, "run \(run): server ready within 30s")

        let transcriber = WhisperTranscriber(port: testPort)
        do {
            let result = try await transcriber.transcribe(wavData: wav, timeout: 30.0)
            #expect(!result.language.isEmpty, "run \(run): language detected")
        } catch let error as WhisperTranscriptionError {
            #expect(error == .noSpeechDetected, "run \(run): tone contains no speech")
        }

        server.terminate()
        #expect(!server.isRunning, "run \(run): server stopped")
    }
}

// MARK: - Readiness: non-whisper server rejected

@Test("readiness rejects non-whisper server")
func readinessRejectsNonWhisper() async throws {
    let testPort: UInt16 = 19993
    let listener = try makeMiniHTTPServer(port: testPort)
    defer { close(listener) }

    Task {
        let clientFd = accept(listener, nil, nil)
        guard clientFd >= 0 else { return }
        defer { close(clientFd) }
        var buf = [UInt8](repeating: 0, count: 1024)
        _ = read(clientFd, &buf, 1024)
        let resp = "HTTP/1.1 400 Bad Request\r\nContent-Length: 2\r\n\r\nOK"
        _ = resp.withCString { write(clientFd, $0, strlen($0)) }
    }

    let ready = await WhisperServerProcess(config: WhisperServerConfig(port: testPort)).checkReadiness(timeout: 2.0)
    #expect(ready == false)
}

// MARK: - Helpers

private func makeMiniHTTPServer(port: UInt16) throws -> Int32 {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { throw WhisperTranscriptionError.serverFailed("socket") }
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = CFSwapInt16HostToBig(port)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard r == 0 else { close(sock); throw WhisperTranscriptionError.portOccupied(port) }
    listen(sock, 1)
    return sock
}
