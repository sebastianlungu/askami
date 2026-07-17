import Foundation
import CryptoKit

public struct WhisperServerConfig: Sendable, Equatable {
    public let executablePath: String
    public let modelPath: String
    public let host: String
    public let port: UInt16
    public let language: String

    public static let expectedModelSize: UInt64 = 59_707_625
    public static let expectedModelSHA256 = "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
    public static let defaultModelName = "ggml-base-q5_1.bin"
    public static let maxResponseBodyBytes = 1_048_576
    public static let maxTextLength = 10_240
    public static let maxLanguageLength: Int = 50

    public init(
        executablePath: String = "/opt/homebrew/bin/whisper-server",
        modelPath: String = Self.defaultModelPath,
        host: String = "127.0.0.1",
        port: UInt16 = 19990,
        language: String = "auto"
    ) {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.host = host
        self.port = port
        self.language = language
    }

    public var resolvedModelPath: String {
        if modelPath.hasPrefix("/") { return modelPath }
        if let env = ProcessInfo.processInfo.environment["JUSTASEC_MODEL_PATH"] {
            if env.hasPrefix("/") { return env }
            let envPath = "\(FileManager.default.currentDirectoryPath)/\(env)"
            if FileManager.default.fileExists(atPath: envPath) { return envPath }
        }
        if let bundleResource = Bundle.main.resourceURL?
            .appendingPathComponent(modelPath).path,
           FileManager.default.fileExists(atPath: bundleResource) {
            return bundleResource
        }
        if let execURL = Bundle.main.executableURL {
            let bundleParent = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let parentModel = bundleParent.appendingPathComponent(modelPath).path
            if FileManager.default.fileExists(atPath: parentModel) {
                return parentModel
            }
        }
        let cwdPath = "\(FileManager.default.currentDirectoryPath)/\(modelPath)"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }
        return modelPath
    }

    public static var defaultModelPath: String {
        "models/\(defaultModelName)"
    }

    public static func sha256OfFile(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 65536)
            guard !chunk.isEmpty else { break }
            hash.update(data: chunk)
        }
        let digest = hash.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func validateModel(at path: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw WhisperTranscriptionError.modelNotFound
        }
        let attrs = try fm.attributesOfItem(atPath: path)
        guard let fileSize = attrs[.size] as? UInt64 else {
            throw WhisperTranscriptionError.modelInvalidSize(actual: 0, expected: expectedModelSize)
        }
        guard fileSize == expectedModelSize else {
            throw WhisperTranscriptionError.modelInvalidSize(actual: fileSize, expected: expectedModelSize)
        }
        let actualHash = try sha256OfFile(at: path)
        guard actualHash == expectedModelSHA256 else {
            throw WhisperTranscriptionError.modelInvalidHash(actual: actualHash, expected: expectedModelSHA256)
        }
    }
}

public enum WhisperTranscriptionError: Error, Sendable, Equatable {
    case executableNotFound
    case modelNotFound
    case modelInvalidSize(actual: UInt64, expected: UInt64)
    case modelInvalidHash(actual: String, expected: String)
    case portOccupied(UInt16)
    case portBindFailed(UInt16, String)
    case serverFailed(String)
    case startupTimeout
    case inferenceTimeout
    case inferenceFailed(String)
    case unexpectedResponse(String)
    case hostNotLoopback(String)
}

public struct WhisperTranscriptionResult: Sendable, Equatable {
    public let text: String
    public let language: String

    public init(text: String, language: String) {
        self.text = text
        self.language = language
    }
}
