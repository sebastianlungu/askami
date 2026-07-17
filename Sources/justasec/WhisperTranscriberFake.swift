import Foundation

public final class WhisperServerProcessFake: WhisperServerProcessProtocol {
    public var isRunning = false
    public var stubLaunchResult: Result<Void, WhisperTranscriptionError> = .success(())
    public var stubPreflightResult: Result<Void, WhisperTranscriptionError> = .success(())
    public var stubReadinessResult = true
    public var stubReadinessDelay: TimeInterval = 0
    public var capturedTerminateCount = 0

    public init() {}

    public func preflightPortCheck() throws {
        switch stubPreflightResult {
        case .success: break
        case .failure(let error): throw error
        }
    }

    public func launch() throws {
        switch stubLaunchResult {
        case .success:
            isRunning = true
        case .failure(let error):
            throw error
        }
    }

    public func terminate() {
        capturedTerminateCount += 1
        isRunning = false
    }

    public func checkReadiness(timeout: TimeInterval) async -> Bool {
        if stubReadinessDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(stubReadinessDelay * 1_000_000_000))
        }
        return stubReadinessResult
    }
}

public final class WhisperTranscriberFake: @unchecked Sendable {
    public var stubResult: Result<WhisperTranscriptionResult, WhisperTranscriptionError> = .success(
        WhisperTranscriptionResult(text: "", language: "english")
    )
    public var capturedWavData: Data?

    public init() {}

    public func transcribe(
        wavData: Data,
        timeout: TimeInterval = 30.0
    ) async throws -> WhisperTranscriptionResult {
        capturedWavData = wavData
        switch stubResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

extension WhisperTranscriberFake: TranscriberProtocol {}
