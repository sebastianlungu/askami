import Foundation

public final class OpenCodeClientFake: @unchecked Sendable {
    public var stubResult: Result<OpenCodeResult, OpenCodeError>
    public var capturedTranscript: String?
    public var capturedLanguage: String?
    public var delay: TimeInterval

    public init(
        result: Result<OpenCodeResult, OpenCodeError> = .success(
            OpenCodeResult(answer: "That is Great Britain.", language: "en")
        ),
        delay: TimeInterval = 0
    ) {
        self.stubResult = result
        self.delay = delay
    }

    public func analyze(transcript: String, language: String? = nil) async throws -> OpenCodeResult {
        capturedTranscript = transcript
        capturedLanguage = language
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        switch stubResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

extension OpenCodeClientFake: ReasonerProtocol {}
