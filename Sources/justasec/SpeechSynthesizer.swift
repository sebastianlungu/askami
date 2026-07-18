import Foundation
@preconcurrency import AVFoundation

private let languageToBCP47: [String: String] = [
    "english": "en-US", "french": "fr-FR", "spanish": "es-ES",
    "german": "de-DE", "italian": "it-IT", "dutch": "nl-NL",
    "portuguese": "pt-PT", "russian": "ru-RU", "japanese": "ja-JP",
    "chinese": "zh-CN", "korean": "ko-KR", "arabic": "ar-SA",
    "hindi": "hi-IN", "turkish": "tr-TR", "polish": "pl-PL",
    "swedish": "sv-SE", "danish": "da-DK", "finnish": "fi-FI",
    "norwegian": "nb-NO", "czech": "cs-CZ", "romanian": "ro-RO",
    "hungarian": "hu-HU", "thai": "th-TH", "vietnamese": "vi-VN",
    "greek": "el-GR", "hebrew": "he-IL", "indonesian": "id-ID",
    "malay": "ms-MY", "ukrainian": "uk-UA", "croatian": "hr-HR",
    "slovak": "sk-SK", "slovenian": "sl-SI", "bulgarian": "bg-BG",
    "serbian": "sr-RS", "lithuanian": "lt-LT", "latvian": "lv-LV",
    "estonian": "et-EE", "icelandic": "is-IS", "maltese": "mt-MT",
    "albanian": "sq-AL", "macedonian": "mk-MK", "bosnian": "bs-BA",
    "afrikaans": "af-ZA", "swahili": "sw-TZ", "zulu": "zu-ZA",
    "amharic": "am-ET", "burmese": "my-MM", "khmer": "km-KH",
    "lao": "lo-LA", "mongolian": "mn-MN", "nepali": "ne-NP",
    "sinhala": "si-LK", "tamil": "ta-IN", "telugu": "te-IN",
    "urdu": "ur-PK", "welsh": "cy-GB", "galician": "gl-ES",
    "basque": "eu-ES", "catalan": "ca-ES",
]

public func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
    let lower = language.lowercased()
    if let bcp47 = languageToBCP47[lower] {
        if let voice = AVSpeechSynthesisVoice(language: bcp47) { return voice }
    }
    if lower.count <= 3 {
        if let voice = AVSpeechSynthesisVoice(language: lower) { return voice }
        for candidate in AVSpeechSynthesisVoice.speechVoices() {
            if candidate.language.hasPrefix(lower) {
                return candidate
            }
        }
    }
    return nil
}

public protocol SpeechDriverProtocol: AnyObject, Sendable {
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechDriverProtocol {}

private enum SpeechState {
    case idle
    case speaking(id: UUID, continuation: CheckedContinuation<SpeechResult, Never>)
}

@MainActor
public final class SpeechSynthesizerActor: @preconcurrency SpeechSynthesizerProtocol {
    private let driver: SpeechDriverProtocol
    private var delegate: SpeechDelegateBridge?
    private var state: SpeechState = .idle
    private var speakTimeoutTask: Task<Void, Never>?

    public static let speakTimeout: TimeInterval = 30.0

    public init(driver: SpeechDriverProtocol = AVSpeechSynthesizer()) {
        self.driver = driver
    }

    @discardableResult
    public func speak(_ text: String, language: String?) async -> SpeechResult {
        guard case .idle = state else { return .failed }

        let utterance = AVSpeechUtterance(string: text)
        if let lang = language, !lang.isEmpty {
            utterance.voice = bestVoice(for: lang)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0

        let speakId = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<SpeechResult, Never>) in
                let bridge = SpeechDelegateBridge(
                    onFinish: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.resumeCompleted(speakId)
                        }
                    },
                    onCancel: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.resumeCancelled(speakId)
                        }
                    }
                )
                delegate = bridge
                driver.delegate = bridge
                state = .speaking(id: speakId, continuation: cont)
                driver.speak(utterance)

                speakTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: UInt64(Self.speakTimeout * 1_000_000_000))
                    self?.timeoutSpeak()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelSpeak()
            }
        }
    }

    public func stop() {
        guard case .speaking(_, let cont) = state else { return }
        _ = driver.stopSpeaking(at: .immediate)
        state = .idle
        delegate = nil
        driver.delegate = nil
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .cancelled)
    }

    private func cancelSpeak() {
        guard case .speaking(_, let cont) = state else { return }
        _ = driver.stopSpeaking(at: .immediate)
        state = .idle
        delegate = nil
        driver.delegate = nil
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .cancelled)
    }

    private func resumeCompleted(_ id: UUID) {
        guard case .speaking(let currentId, let cont) = state, currentId == id
        else { return }
        state = .idle
        delegate = nil
        driver.delegate = nil
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .completed)
    }

    private func resumeCancelled(_ id: UUID) {
        guard case .speaking(let currentId, let cont) = state, currentId == id
        else { return }
        _ = driver.stopSpeaking(at: .immediate)
        state = .idle
        delegate = nil
        driver.delegate = nil
        speakTimeoutTask?.cancel()
        speakTimeoutTask = nil
        cont.resume(returning: .cancelled)
    }

    private func timeoutSpeak() {
        guard case .speaking(_, let cont) = state else { return }
        _ = driver.stopSpeaking(at: .immediate)
        state = .idle
        delegate = nil
        driver.delegate = nil
        speakTimeoutTask = nil
        cont.resume(returning: .failed)
    }
}

private final class SpeechDelegateBridge: NSObject, AVSpeechSynthesizerDelegate,
    @unchecked Sendable {
    private let onFinish: @Sendable () -> Void
    private let onCancel: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void, onCancel: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        onFinish()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        onCancel()
    }
}
