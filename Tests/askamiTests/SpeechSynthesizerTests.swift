import Testing
import Foundation
import os.lock
@testable import askami

// MARK: - Fake tests (unchanged)

@Test("SpeechSynthesizerFake records spoken texts")
func fakeRecordsSpoken() async {
    let fake = SpeechSynthesizerFake()
    _ = await fake.speak("Hello", language: "en")
    _ = await fake.speak("Bonjour", language: "fr")
    #expect(fake.spokenTexts.count == 2)
    #expect(fake.spokenTexts[0].0 == "Hello")
    #expect(fake.spokenTexts[0].1 == "en")
    #expect(fake.spokenTexts[1].0 == "Bonjour")
    #expect(fake.spokenTexts[1].1 == "fr")
}

@Test("SpeechSynthesizerFake stop is safe")
func fakeStopIsSafe() async {
    let fake = SpeechSynthesizerFake()
    fake.stop()
}

@Test("SpeechSynthesizer conforms to SpeechSynthesizerProtocol")
func speechSynthesizerConforms() {
    func accept<T: SpeechSynthesizerProtocol>(_: T.Type) {}
    accept(SpeechSynthesizerActor.self)
    accept(SpeechSynthesizerFake.self)
}

// MARK: - TestSpeechDriver basic tests

@Test("speak completes with .completed via autoComplete")
@MainActor
func speakCompletesWithCompleted() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteResult = .completed
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(driver.capturedText == "Hello")
    #expect(driver.capturedLanguage == "en")
    #expect(result == .completed)
}

@Test("language profiles select matching phonemizer and Kokoro voice")
func languageProfilesSelectVoiceAndPhonemizer() {
    let english = KokoroLanguageProfile.resolve("english")
    #expect(english.voice == "af_heart")
    #expect(english.espeakVoice == nil)

    let portuguese = KokoroLanguageProfile.resolve("pt")
    #expect(portuguese.voice == "pf_dora")
    #expect(portuguese.espeakVoice == "pt-br")

    let french = KokoroLanguageProfile.resolve("french")
    #expect(french.voice == "ff_siwis")
    #expect(french.espeakVoice == "fr-fr")
}

@Test("eSpeak phonemizes Portuguese without putting text in argv",
      .enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/espeak-ng")))
func espeakPhonemizesPortuguese() throws {
    let ipa = try ESpeakPhonemizer.phonemize(
        "A capital de Portugal é Lisboa.",
        voice: "pt-br"
    )
    #expect(!ipa.isEmpty)
    #expect(ipa != "A capital de Portugal é Lisboa.")
    #expect(ipa.contains("ˈ"))
}

@Test("speak completes with .failed via autoComplete")
@MainActor
func speakCompletesWithFailed() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteResult = .failed
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(result == .failed)
}

@Test("speak completes with .cancelled via autoComplete")
@MainActor
func speakCompletesWithCancelled() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteResult = .cancelled
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(result == .cancelled)
}

@Test("second concurrent speak returns .failed")
@MainActor
func secondConcurrentSpeakFails() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteDelay = 0.5
    let synth = SpeechSynthesizerActor(driver: driver)

    let first = Task { await synth.speak("First", language: "en") }
    try? await Task.sleep(nanoseconds: 50_000_000)

    let second = await synth.speak("Second", language: "en")
    #expect(second == .failed)

    _ = await first.value
}

@Test("stop during speak returns .cancelled and calls driver.stop")
@MainActor
func stopDuringSpeak() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteDelay = 0.5
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 50_000_000)

    synth.stop()

    let result = await task.value
    #expect(result == .cancelled)
    #expect(driver.stopCallCount == 1)
}

@Test("task cancellation cancels driver and returns .cancelled")
@MainActor
func taskCancelsDriver() async {
    let driver = TestSpeechDriver()
    driver.autoCompleteDelay = -1
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 50_000_000)

    task.cancel()
    let result = await task.value
    #expect(result == .cancelled)
    #expect(driver.stopCallCount == 1)
}

// MARK: - Timeout hinting tests

@Test("actor uses timeoutHint from driver when > 30")
@MainActor
func actorUsesExtendedTimeoutForFirstDownload() async {
    let driver = TestSpeechDriver()
    driver.timeoutHintOverride = 300
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(result == .completed)
}

@Test("actor uses default timeout for cached driver")
@MainActor
func actorUsesDefaultTimeoutForCached() async {
    let driver = TestSpeechDriver()
    driver.timeoutHintOverride = 30
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(result == .completed)
}

// MARK: - Stream failure tests

@Test("speak returns .failed when driver shouldStreamFail")
@MainActor
func speakReturnsFailedOnStreamFail() async {
    let driver = TestSpeechDriver()
    driver.shouldStreamFail = true
    let synth = SpeechSynthesizerActor(driver: driver)

    let result = await synth.speak("Hello", language: "en")
    #expect(result == .failed)
}

// MARK: - Per-invocation timeout resolution

private final class HintTrackingDriver: SpeechDriverProtocol, TimeoutHinting, @unchecked Sendable {
    let wrapped = TestSpeechDriver()
    private(set) var accessCount = 0

    var timeoutHint: TimeInterval {
        accessCount += 1
        return wrapped.timeoutHintOverride
    }

    func speak(
        _ text: String,
        language: String?,
        beforePlayback: PlaySoundEffect?
    ) async -> SpeechResult {
        await wrapped.speak(
            text,
            language: language,
            beforePlayback: beforePlayback
        )
    }
    func stop() { wrapped.stop() }
}

@Test("speak reads timeoutHint fresh per invocation, not cached at init")
@MainActor
func speakReadsTimeoutFreshPerCall() async {
    let tracker = HintTrackingDriver()
    tracker.wrapped.autoCompleteResult = .completed
    let synth = SpeechSynthesizerActor(driver: tracker)

    #expect(tracker.accessCount == 0, "timeoutHint should not be read during init")

    _ = await synth.speak("First", language: "en")
    #expect(tracker.accessCount == 1, "timeoutHint must be read once during first speak")

    _ = await synth.speak("Second", language: "en")
    #expect(tracker.accessCount == 2, "timeoutHint must be read once per speak call, not cached")
}

// MARK: - KokoroSpeechDriver timeout hint

@Test("KokoroSpeechDriver timeoutHint is 30 or 300 based on download state")
@MainActor
func kokoroTimeoutHint() {
    let driver = KokoroSpeechDriver()
    let hint = driver.timeoutHint
    #expect(hint == 30 || hint == 300, "timeoutHint should be 30 (cached) or 300 (needs download), got \(hint)")
}

@Test("KokoroSpeechDriver conforms to TimeoutHinting")
@MainActor
func kokoroConformsToTimeoutHinting() {
    #expect((KokoroSpeechDriver() as Any) is TimeoutHinting)
    #expect((TestSpeechDriver() as Any) is TimeoutHinting)
}

// MARK: - forceCPU engine factory tests

@Test("KokoroSpeechDriver engine factory receives forceCPU: true")
func kokoroEngineFactoryForceCPU() async {
    let capturedDir = OSAllocatedUnfairLock<URL?>(initialState: nil)
    let capturedForceCPU = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    let driver = KokoroSpeechDriver()
    driver._engineFactory = { dir, forceCPU in
        capturedDir.withLock { $0 = dir }
        capturedForceCPU.withLock { $0 = forceCPU }
        struct E: Error {}; throw E()
    }
    let result = await driver.speak("Hello")
    #expect(result == .failed)
    let cpuOnly = capturedForceCPU.withLock { $0 }
    #expect(cpuOnly == true, "forceCPU must be true for production, got \(cpuOnly.map(String.init) ?? "nil")")
    let dir = capturedDir.withLock { $0 }
    #expect(dir != nil)
}

@Test("KokoroSpeechDriver engine factory not set uses real engine path — no crash from factory assertion")
@MainActor
func kokoroEngineFactoryNotSetDoesNotCallFactory() {
    // The default factory is nil, meaning real KokoroEngine init is used.
    // This test just confirms no factory is set by default.
    let driver = KokoroSpeechDriver()
    #expect(driver._engineFactory == nil)
}

@Test("kokoroUseCPUOnly constant is true")
@MainActor
func kokoroUseCPUOnlyConstantIsTrue() {
    #expect(kokoroUseCPUOnly == true, "CPU-only policy constant must be true on this hardware")
}
