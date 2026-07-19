import Foundation

public struct OpenCodeConfig: Sendable {
    public let executablePath: String
    public let model: String
    public let timeout: TimeInterval
    public let maxAnswerChars: Int
    public let maxSentences: Int
    public let maxInputBytes: Int
    public let maxAccumulatorBytes: Int

    public init(
        executablePath: String = "/opt/homebrew/bin/opencode",
        model: String = "opencode-go/deepseek-v4-flash",
        timeout: TimeInterval = 30.0,
        maxAnswerChars: Int = 2000,
        maxSentences: Int = 2,
        maxInputBytes: Int = 50_000,
        maxAccumulatorBytes: Int = 100_000
    ) {
        self.executablePath = executablePath
        self.model = model
        self.timeout = timeout
        self.maxAnswerChars = maxAnswerChars
        self.maxSentences = maxSentences
        self.maxInputBytes = maxInputBytes
        self.maxAccumulatorBytes = maxAccumulatorBytes
    }
}

public enum OpenCodeError: Error, Sendable, Equatable {
    case executableNotFound
    case launchFailed(String)
    case timeout
    case processTerminated(Int32)
    case emptyResponse
    case malformedResponse(String)
    case answerTooLong(Int)
    case tooManySentences(Int)
    case noAssistantResponse
    case inputTooLarge(Int)
    case responseOversized
}

public struct OpenCodeResult: Sendable, Equatable {
    public let answer: String
    public let language: String?

    public init(answer: String, language: String?) {
        self.answer = answer
        self.language = language
    }
}
