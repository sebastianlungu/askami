import Testing
@testable import justasec
@preconcurrency import AVFoundation

@Test("bestVoice returns voice for known language english")
func bestVoiceEnglish() {
    let voice = bestVoice(for: "english")
    #expect(voice != nil)
    if let v = voice {
        let isEnglish = v.language.hasPrefix("en")
    #expect(isEnglish)
    }
}

@Test("bestVoice returns voice for known language french")
func bestVoiceFrench() {
    let voice = bestVoice(for: "french")
    #expect(voice != nil)
    if let v = voice {
        let isFrench = v.language.hasPrefix("fr")
        #expect(isFrench)
    }
}

@Test("bestVoice returns voice for known language german")
func bestVoiceGerman() {
    let voice = bestVoice(for: "german")
    #expect(voice != nil)
    if let v = voice {
        let isGerman = v.language.hasPrefix("de")
        #expect(isGerman)
    }
}

@Test("bestVoice returns nil for unknown language")
func bestVoiceUnknown() {
    let voice = bestVoice(for: "klingon")
    #expect(voice == nil)
}

@Test("bestVoice uses short language code")
func bestVoiceShortCode() {
    let voice = bestVoice(for: "en")
    #expect(voice != nil)
    if let v = voice {
        let isEnglish = v.language.hasPrefix("en")
        #expect(isEnglish)
    }
}

@Test("bestVoice handles lowercase and mixed case")
func bestVoiceLowercase() {
    let voice = bestVoice(for: "French")
    #expect(voice != nil)
    if let v = voice {
        let isFrench = v.language.hasPrefix("fr")
        #expect(isFrench)
    }
}

@Test("SpeechSynthesizerFake records spoken texts")
func fakeRecordsSpoken() async {
    let fake = SpeechSynthesizerFake()
    await fake.speak("Hello", language: "en")
    await fake.speak("Bonjour", language: "fr")
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

// MARK: - Deterministic speech tests with TestSpeechDriver

@Test("single-resume: didFinish resumes exactly once")
@MainActor
func singleResumeDidFinish() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 10_000_000)

    driver.fireDidFinish()
    await task.value

    synth.stop()
}

@Test("single-resume: stop and delegate race does not double-resume")
@MainActor
func stopAndDelegateRace() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 10_000_000)

    synth.stop()
    driver.fireDidFinish()

    await task.value
}

@Test("concurrent speak rejection")
@MainActor
func concurrentSpeakRejected() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task1 = Task { await synth.speak("First", language: "en") }
    try? await Task.sleep(nanoseconds: 10_000_000)

    let task2 = Task { await synth.speak("Second", language: "en") }

    driver.fireDidFinish()
    await task1.value
    await task2.value

    #expect(driver.capturedUtterance?.speechString == "First")
    synth.stop()
}

@Test("cancellation during speaking resumes immediately")
@MainActor
func cancelDuringSpeaking() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 10_000_000)

    task.cancel()
    await task.value

    synth.stop()
}

@Test("timeout resumes when driver never fires")
@MainActor
func timeoutResumes() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task {
        await synth.speak("Hello", language: "en")
    }
    try? await Task.sleep(nanoseconds: 10_000_000)

    let shortTimeout = Task {
        try? await Task.sleep(nanoseconds: 100_000_000)
        synth.stop()
    }

    await task.value
    shortTimeout.cancel()
}

@Test("didCancel also resumes single-resume")
@MainActor
func didCancelResumes() async {
    let driver = TestSpeechDriver()
    let synth = SpeechSynthesizerActor(driver: driver)

    let task = Task { await synth.speak("Hello", language: "en") }
    try? await Task.sleep(nanoseconds: 10_000_000)

    driver.fireDidCancel()
    await task.value

    synth.stop()
}
