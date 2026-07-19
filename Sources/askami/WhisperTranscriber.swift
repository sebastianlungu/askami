import Foundation

public struct WhisperTranscriber: Sendable {
    private let host: String
    private let port: UInt16
    private let session: URLSession

    public init(host: String = "127.0.0.1", port: UInt16 = 19990) {
        self.host = host
        self.port = port
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)
    }

    public func transcribe(
        wavData: Data,
        timeout: TimeInterval = 30.0
    ) async throws -> WhisperTranscriptionResult {
        let request = Self.makeInferenceRequest(
            wavData: wavData,
            host: host,
            port: port,
            timeout: timeout
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw WhisperTranscriptionError.inferenceTimeout
        } catch {
            throw WhisperTranscriptionError.inferenceFailed(
                "Request failed: \(error.localizedDescription)"
            )
        }

        guard data.count < WhisperServerConfig.maxResponseBodyBytes else {
            throw WhisperTranscriptionError.unexpectedResponse(
                "Response body too large: \(data.count) bytes"
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw WhisperTranscriptionError.unexpectedResponse("Not an HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            throw WhisperTranscriptionError.inferenceFailed(
                "HTTP \(http.statusCode)"
            )
        }

        return try Self.parseResponse(data: data)
    }

    public static func makeInferenceRequest(
        wavData: Data,
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) -> URLRequest {
        let boundary = "WhisperBoundary_\(UUID().uuidString)"
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(#"Content-Disposition: form-data; name="file"; filename="audio.wav""#.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(#"Content-Disposition: form-data; name="response_format""#.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("verbose_json".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(#"Content-Disposition: form-data; name="language""#.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("auto".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "http://\(host):\(port)/inference")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = timeout
        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        return req
    }

    public static func parseResponse(data: Data) throws -> WhisperTranscriptionResult {
        guard !data.isEmpty else {
            throw WhisperTranscriptionError.unexpectedResponse("Empty response")
        }
        guard data.count < WhisperServerConfig.maxResponseBodyBytes else {
            throw WhisperTranscriptionError.unexpectedResponse(
                "Response body too large: \(data.count) bytes"
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperTranscriptionError.unexpectedResponse("Invalid JSON")
        }
        guard let text = json["text"] as? String else {
            throw WhisperTranscriptionError.unexpectedResponse("Missing text field")
        }
        guard text.count < WhisperServerConfig.maxTextLength else {
            throw WhisperTranscriptionError.unexpectedResponse(
                "Text field too long: \(text.count) chars"
            )
        }
        let cleanedText = cleanTranscript(text)
        guard !cleanedText.isEmpty else {
            throw WhisperTranscriptionError.noSpeechDetected
        }
        let language: String
        if let lang = json["language"] as? String, !lang.isEmpty {
            guard lang.count < WhisperServerConfig.maxLanguageLength else {
                throw WhisperTranscriptionError.unexpectedResponse(
                    "Language field too long: \(lang.count) chars"
                )
            }
            language = lang
        } else if let detected = json["detected_language"] as? String, !detected.isEmpty {
            guard detected.count < WhisperServerConfig.maxLanguageLength else {
                throw WhisperTranscriptionError.unexpectedResponse(
                    "Language field too long: \(detected.count) chars"
                )
            }
            language = detected
        } else {
            throw WhisperTranscriptionError.unexpectedResponse("Missing language field")
        }
        return WhisperTranscriptionResult(text: cleanedText, language: language)
    }

    public static func cleanTranscript(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isAnnotation($0) }
            .joined(separator: " ")
    }

    private static func isAnnotation(_ line: String) -> Bool {
        let pairs: [(Character, Character)] = [("[", "]"), ("(", ")")]
        if pairs.contains(where: { line.first == $0.0 && line.last == $0.1 }) {
            return true
        }
        return line.allSatisfy { $0 == "♪" || $0.isWhitespace }
    }
}
