import Testing
import CoreMedia
@testable import justasec

@Test("idle gate does not discard any source")
func idleNoDiscard() {
    let gate = MicSuppressionGate()
    #expect(!gate.isSuppressing)
    #expect(!gate.shouldDiscard(source: .microphone))
    #expect(!gate.shouldDiscard(source: .systemAudio))
}

@Test("suppressing discards microphone but not system audio")
func suppressingDiscardsMic() {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    #expect(gate.isSuppressing)
    #expect(gate.shouldDiscard(source: .microphone))
    #expect(!gate.shouldDiscard(source: .systemAudio))
}

@Test("suppressing end suppression cycle returns to idle")
func suppressingCycle() {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    #expect(gate.isSuppressing)
    #expect(gate.shouldDiscard(source: .microphone))
    gate.startSuppression()
    #expect(gate.shouldDiscard(source: .microphone))
}

@Test("settle period discards microphone but not system")
func settleDiscardsMic() async {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    #expect(gate.isSuppressing)

    await gate.endSuppression(after: 0.01)
    #expect(!gate.isSuppressing)
    #expect(!gate.shouldDiscard(source: .microphone))
}

@Test("settle expires and returns to idle")
func settleExpires() async {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    #expect(gate.shouldDiscard(source: .microphone))
    await gate.endSuppression(after: 0.005)
    #expect(!gate.isSuppressing)
    #expect(!gate.shouldDiscard(source: .microphone))
    #expect(!gate.shouldDiscard(source: .systemAudio))
}

@Test("multiple start suppression is idempotent")
func multipleStart() {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    gate.startSuppression()
    gate.startSuppression()
    #expect(gate.isSuppressing)
    #expect(gate.shouldDiscard(source: .microphone))
}

@Test("start after settle cycle restarts suppression")
func startAfterSettle() async {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    await gate.endSuppression(after: 0.005)
    #expect(!gate.isSuppressing)

    gate.startSuppression()
    #expect(gate.isSuppressing)
    #expect(gate.shouldDiscard(source: .microphone))
}

@Test("suppression preserves system audio payloads")
func suppressionPreservesSystem() {
    let gate = MicSuppressionGate()
    gate.startSuppression()
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let micPayload = AudioSamplePayload(
        data: Data([0]), timestamp: .zero, format: format, source: .microphone
    )
    let sysPayload = AudioSamplePayload(
        data: Data([1]), timestamp: .zero, format: format, source: .systemAudio
    )
    #expect(gate.shouldDiscard(source: micPayload.source))
    #expect(!gate.shouldDiscard(source: sysPayload.source))
}
