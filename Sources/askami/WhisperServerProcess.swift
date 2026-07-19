import Foundation
import os.lock

private struct WhisperProcessState: Sendable {
    var process: Process?
    var isRunning = false
}

public struct WhisperServerProcessArguments {
    public static func makeArguments(config: WhisperServerConfig) -> [String] {
        [
            "--host", config.host,
            "--port", String(config.port),
            "--model", config.resolvedModelPath,
            "-l", config.language,
        ]
    }
}

public protocol WhisperServerProcessProtocol: AnyObject {
    var isRunning: Bool { get }
    func launch() throws
    func terminate()
    func checkReadiness(timeout: TimeInterval) async -> Bool
}

private let _cleanupLock = OSAllocatedUnfairLock(initialState: Optional<WhisperServerProcess>.none)
private let _atexitRegState = OSAllocatedUnfairLock(initialState: false)

private func _whisperAtexitHandler() {
    let proc = _cleanupLock.withLock { state -> WhisperServerProcess? in
        defer { state = nil }
        return state
    }
    proc?.forceTerminate()
}

private func _ensureAtexitRegistered() {
    _atexitRegState.withLock { already in
        guard !already else { return }
        already = true
        atexit(_whisperAtexitHandler)
    }
}

public final class WhisperServerProcess: Sendable, WhisperServerProcessProtocol {
    private let state = OSAllocatedUnfairLock(initialState: WhisperProcessState())
    private let config: WhisperServerConfig

    public var isRunning: Bool {
        state.withLock { s in s.isRunning }
    }

    public static func makeArguments(config: WhisperServerConfig) -> [String] {
        WhisperServerProcessArguments.makeArguments(config: config)
    }

    public init(config: WhisperServerConfig) {
        self.config = config
    }

    deinit {
        terminate()
    }

    public func preflightPortCheck() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return }
        defer { close(sock) }
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(config.port)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw WhisperTranscriptionError.portOccupied(config.port)
        }
    }

    public func validate() throws {
        guard config.host == "127.0.0.1" else {
            throw WhisperTranscriptionError.hostNotLoopback(config.host)
        }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: config.executablePath) else {
            throw WhisperTranscriptionError.executableNotFound
        }
        try WhisperServerConfig.validateModel(at: config.resolvedModelPath)
    }

    public func launch() throws {
        try validate()
        try preflightPortCheck()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.executablePath)
        proc.arguments = Self.makeArguments(config: config)

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let outFH = outPipe.fileHandleForReading
        let errFH = errPipe.fileHandleForReading

        outFH.readabilityHandler = { handle in
            let _ = try? handle.read(upToCount: 65536)
        }
        errFH.readabilityHandler = { handle in
            let _ = try? handle.read(upToCount: 65536)
        }

        proc.terminationHandler = { _ in }

        do {
            try proc.run()
        } catch {
            outFH.readabilityHandler = nil
            errFH.readabilityHandler = nil
            throw WhisperTranscriptionError.serverFailed(
                "Failed to launch server: \(error.localizedDescription)"
            )
        }

        state.withLock { s in s.process = proc; s.isRunning = true }
        _cleanupLock.withLock { c in c = self }
        _ensureAtexitRegistered()
    }

    public func terminate() {
        let captured = state.withLock { s -> Process? in
            guard let p = s.process else { return nil }
            defer { s.process = nil; s.isRunning = false }
            return p
        }
        guard let proc = captured else { return }
        guard proc.isRunning else {
            cleanupPipeHandlers(proc)
            return
        }
        cleanupPipeHandlers(proc)
        // SIG_IGN is inherited from the parent (proven empirically), so
        // interrupt()/terminate() may have NO effect on the child.
        // We try them briefly for cooperative processes, but SIGKILL is
        // the only guaranteed path on this host.
        proc.interrupt()
        if pollExit(proc, timeout: 0.5) { return }
        proc.terminate()
        if pollExit(proc, timeout: 0.5) { return }
        kill(pid_t(proc.processIdentifier), SIGKILL)
        proc.waitUntilExit()
    }

    public func terminateAsync() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached {
                self.terminate()
                cont.resume()
            }
        }
    }

    private func cleanupPipeHandlers(_ proc: Process) {
        if let outPipe = proc.standardOutput as? Pipe {
            outPipe.fileHandleForReading.readabilityHandler = nil
        }
        if let errPipe = proc.standardError as? Pipe {
            errPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func pollExit(_ proc: Process, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline, proc.isRunning {
            usleep(50_000)
        }
        return !proc.isRunning
    }

    func forceTerminate() {
        guard let proc = state.withLock({ s -> Process? in
            defer { s.process = nil; s.isRunning = false }
            return s.process
        }) else { return }
        guard proc.isRunning else { return }
        cleanupPipeHandlers(proc)
        // SIG_IGN is inherited; SIGTERM/SIGINT have no effect.  Send SIGKILL directly.
        kill(pid_t(proc.processIdentifier), SIGKILL)
        if !pollExit(proc, timeout: 1.0) {
            // Last-reset synchronous reap (bounded because process is already killed)
            proc.waitUntilExit()
        }
    }

    public func checkReadiness(timeout: TimeInterval) async -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            guard state.withLock({ s in s.isRunning }) else { return false }
            do {
                let url = URL(string: "http://\(config.host):\(config.port)/inference")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.httpBody = Data()
                req.timeoutInterval = 1.0
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                guard data.count < WhisperServerConfig.maxResponseBodyBytes else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                guard let server = http.allHeaderFields["Server"] as? String,
                      server.lowercased().contains("whisper") else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                return true
            } catch {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        return false
    }
}

public extension WhisperServerProcess {
    static func setupGlobalCleanup() {
        _ensureAtexitRegistered()
    }
}
