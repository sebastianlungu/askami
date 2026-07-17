import Testing
import CoreMedia
import Foundation
@testable import justasec

// MARK: - AudioStreamFormat Tests

@Test("AudioStreamFormat equality")
func streamFormatEquality() {
    let a = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let b = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let c = AudioStreamFormat(sampleRate: 44100, channelCount: 2, bytesPerFrame: 2)
    #expect(a == b)
    #expect(a != c)
}

@Test("AudioStreamFormat durationForByteCount")
func streamFormatDuration() {
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let duration = format.durationForByteCount(192000)
    #expect(duration == 1.0)
}

@Test("AudioStreamFormat durationForByteCount zero rate")
func streamFormatDurationZeroRate() {
    let format = AudioStreamFormat(sampleRate: 0, channelCount: 1, bytesPerFrame: 4)
    let duration = format.durationForByteCount(100)
    #expect(duration == 0)
}

// MARK: - AudioSamplePayload Tests

@Test("AudioSamplePayload construction and access")
func samplePayloadConstruction() {
    let data = Data([0x00, 0x01, 0x02, 0x03])
    let timestamp = CMTime(value: 100, timescale: 48000)
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let source = AudioSource.microphone

    let payload = AudioSamplePayload(
        data: data,
        timestamp: timestamp,
        format: format,
        source: source
    )

    #expect(payload.data == data)
    #expect(payload.timestamp == timestamp)
    #expect(payload.format == format)
    #expect(payload.source == source)
}

@Test("AudioSamplePayload is Sendable")
func samplePayloadSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(AudioSamplePayload.self)
}

@Test("AudioSource raw values")
func audioSourceRawValues() {
    #expect(AudioSource.microphone.rawValue == "microphone")
    #expect(AudioSource.systemAudio.rawValue == "systemAudio")
}

// MARK: - AudioCaptureError Tests

@Test("AudioCaptureError equality")
func captureErrorEquality() {
    #expect(AudioCaptureError.permissionDenied("mic") == AudioCaptureError.permissionDenied("mic"))
    #expect(AudioCaptureError.permissionDenied("mic") != AudioCaptureError.permissionDenied("other"))
    #expect(AudioCaptureError.streamFailed("err") == AudioCaptureError.streamFailed("err"))
    #expect(AudioCaptureError.unsupported == AudioCaptureError.unsupported)
    #expect(AudioCaptureError.streamInterrupted("x") == AudioCaptureError.streamInterrupted("x"))
}

@Test("AudioCaptureError is Sendable")
func captureErrorSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(AudioCaptureError.self)
}

// MARK: - FormatChangeTracker Tests

@Test("FormatChangeTracker returns false on first registration")
func formatTrackerFirstRegistration() {
    let tracker = FormatChangeTracker()
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let result = tracker.updateIfChanged(format, source: .microphone)
    #expect(!result, "First registration should not be reported as a change")
}

@Test("FormatChangeTracker returns false for same format")
func formatTrackerSameFormat() {
    let tracker = FormatChangeTracker()
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    _ = tracker.updateIfChanged(format, source: .microphone)
    let result = tracker.updateIfChanged(format, source: .microphone)
    #expect(!result, "Same format should not be reported as a change")
}

@Test("FormatChangeTracker returns true for changed format")
func formatTrackerChangedFormat() {
    let tracker = FormatChangeTracker()
    let original = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let changed = AudioStreamFormat(sampleRate: 44100, channelCount: 2, bytesPerFrame: 2)

    _ = tracker.updateIfChanged(original, source: .microphone)
    let result = tracker.updateIfChanged(changed, source: .microphone)
    #expect(result, "Changed format should be reported as a change")
}

@Test("FormatChangeTracker tracks sources independently")
func formatTrackerIndependentSources() {
    let tracker = FormatChangeTracker()
    let fmtA = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let fmtB = AudioStreamFormat(sampleRate: 44100, channelCount: 2, bytesPerFrame: 2)
    let fmtC = AudioStreamFormat(sampleRate: 96000, channelCount: 1, bytesPerFrame: 4)

    _ = tracker.updateIfChanged(fmtA, source: .microphone)
    _ = tracker.updateIfChanged(fmtB, source: .systemAudio)

    let micChange = tracker.updateIfChanged(fmtC, source: .microphone)
    let sysChange = tracker.updateIfChanged(fmtC, source: .systemAudio)

    #expect(micChange, "Microphone format switch from A to C is a change")
    #expect(sysChange, "System format switch from B to C is a change")
}

@Test("FormatChangeTracker returns true only on actual difference")
func formatTrackerOnlyOnDifference() {
    let tracker = FormatChangeTracker()
    let fmt = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)

    _ = tracker.updateIfChanged(fmt, source: .microphone)
    _ = tracker.updateIfChanged(fmt, source: .systemAudio)

    let firstRepeat = tracker.updateIfChanged(fmt, source: .microphone)
    let secondRepeat = tracker.updateIfChanged(fmt, source: .systemAudio)

    #expect(!firstRepeat)
    #expect(!secondRepeat)
}

// MARK: - Protocol Conformance Tests

@Test("AudioCaptureSession conforms to AudioCaptureSessionProtocol")
func realSessionConforms() {
    func acceptProtocol<T: AudioCaptureSessionProtocol>(_: T.Type) {}
    acceptProtocol(AudioCaptureSession.self)
}

@Test("AudioCaptureSessionFake conforms to AudioCaptureSessionProtocol")
@MainActor
func fakeSessionConforms() {
    func acceptProtocol<T: AudioCaptureSessionProtocol>(_: T.Type) {}
    acceptProtocol(AudioCaptureSessionFake.self)
}

@Test("Protocol existential is usable as app storage type")
@MainActor
func appStoresProtocolType() {
    let session: (any AudioCaptureSessionProtocol)? = AudioCaptureSessionFake(
        onSample: { _ in }, onError: { _ in }
    )
    #expect(session != nil)
}

// MARK: - Lifecycle Sequencing Tests (via Fake)

@Test("fake start after stop completes")
@MainActor
func fakeStartAfterStop() async throws {
    let fake = AudioCaptureSessionFake(onSample: { _ in }, onError: { _ in })

    try await fake.start()
    #expect(fake.isRunning)

    await fake.stop()
    #expect(!fake.isRunning)
    #expect(!fake.isStopping)

    try await fake.start()
    #expect(fake.isRunning)
}

@Test("fake stop while idle is no-op")
@MainActor
func fakeStopWhileIdle() async {
    let fake = AudioCaptureSessionFake(onSample: { _ in }, onError: { _ in })

    #expect(!fake.isRunning)
    await fake.stop()
    #expect(!fake.isRunning)
    #expect(!fake.isStopping)
}

@Test("fake multiple stop calls are safe")
@MainActor
func fakeMultipleStops() async throws {
    let fake = AudioCaptureSessionFake(onSample: { _ in }, onError: { _ in })

    try await fake.start()
    await fake.stop()
    await fake.stop()
    await fake.stop()

    #expect(!fake.isRunning)
    #expect(!fake.isStopping)
}

@Test("fake stop surfaces injected stop error")
@MainActor
func fakeStopSurfacesError() async {
    let receivedError = ManagedBox<AudioCaptureError?>(nil)
    let fake = AudioCaptureSessionFake(
        onSample: { _ in },
        onError: { error in receivedError.value = error }
    )
    fake.injectStopError(.streamFailed("stop failure"))

    try? await fake.start()
    await fake.stop()

    #expect(receivedError.value != nil)
    #expect(receivedError.value == .streamFailed("stop failure"))
}

// MARK: - AudioCaptureSessionFake Injection Tests

@Test("fake starts and stops")
@MainActor
func fakeStartStop() async throws {
    let fake = AudioCaptureSessionFake(onSample: { _ in }, onError: { _ in })

    #expect(!fake.isRunning)
    try await fake.start()
    #expect(fake.isRunning)
    await fake.stop()
    #expect(!fake.isRunning)
}

@Test("fake delivers microphone samples through handler")
@MainActor
func fakeDeliversMicrophoneSamples() async throws {
    let received = ManagedBox(false)

    let fake = AudioCaptureSessionFake(
        onSample: { payload in
            if payload.source == .microphone { received.value = true }
        },
        onError: { _ in }
    )

    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let payload = AudioSamplePayload(
        data: Data(repeating: 0, count: 4),
        timestamp: CMTime(value: 0, timescale: 48000),
        format: format,
        source: .microphone
    )

    fake.injectSample(payload)
    #expect(received.value)
}

@Test("fake delivers system audio samples through handler")
@MainActor
func fakeDeliversSystemAudioSamples() async throws {
    let received = ManagedBox(false)

    let fake = AudioCaptureSessionFake(
        onSample: { payload in
            if payload.source == .systemAudio { received.value = true }
        },
        onError: { _ in }
    )

    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let payload = AudioSamplePayload(
        data: Data(repeating: 0, count: 4),
        timestamp: CMTime(value: 0, timescale: 48000),
        format: format,
        source: .systemAudio
    )

    fake.injectSample(payload)
    #expect(received.value)
}

@Test("fake delivers errors through error handler")
@MainActor
func fakeDeliversErrors() async throws {
    let received = ManagedBox<AudioCaptureError?>(nil)

    let fake = AudioCaptureSessionFake(
        onSample: { _ in },
        onError: { error in received.value = error }
    )

    fake.injectError(.permissionDenied("test"))
    #expect(received.value == .permissionDenied("test"))
}

@Test("fake delivers format changes through format change handler")
@MainActor
func fakeDeliversFormatChanges() async throws {
    let receivedFormat = ManagedBox<AudioStreamFormat?>(nil)
    let receivedSource = ManagedBox<AudioSource?>(nil)

    let fake = AudioCaptureSessionFake(
        onSample: { _ in },
        onError: { _ in },
        onFormatChange: { format, source in
            receivedFormat.value = format
            receivedSource.value = source
        }
    )

    let format = AudioStreamFormat(sampleRate: 44100, channelCount: 2, bytesPerFrame: 2)
    fake.injectFormatChange(format: format, source: .microphone)
    #expect(receivedFormat.value?.sampleRate == 44100)
    #expect(receivedSource.value == .microphone)
}

@Test("fake routes microphone and system audio to separate sources")
@MainActor
func fakeSeparateSourceRouting() async throws {
    let micReceived = ManagedBox(false)
    let sysReceived = ManagedBox(false)

    let fake = AudioCaptureSessionFake(
        onSample: { payload in
            switch payload.source {
            case .microphone: micReceived.value = true
            case .systemAudio: sysReceived.value = true
            }
        },
        onError: { _ in }
    )

    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)

    fake.injectSample(AudioSamplePayload(
        data: Data(repeating: 0, count: 4),
        timestamp: CMTime(value: 0, timescale: 48000),
        format: format,
        source: .microphone
    ))

    fake.injectSample(AudioSamplePayload(
        data: Data(repeating: 1, count: 4),
        timestamp: CMTime(value: 100, timescale: 48000),
        format: format,
        source: .systemAudio
    ))

    #expect(micReceived.value)
    #expect(sysReceived.value)
}

@Test("fake callbacks run synchronously on caller")
@MainActor
func fakeSynchronousCallbacks() {
    let called = ManagedBox(false)

    let fake = AudioCaptureSessionFake(
        onSample: { _ in called.value = true },
        onError: { _ in }
    )

    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4)
    let payload = AudioSamplePayload(
        data: Data(repeating: 0, count: 4),
        timestamp: CMTime(value: 0, timescale: 48000),
        format: format,
        source: .microphone
    )

    fake.injectSample(payload)
    #expect(called.value, "Callback should execute before injectSample returns")
}

@Test("fake injectError with all error cases")
@MainActor
func fakeAllErrorCases() async throws {
    let errors = ManagedBox<[AudioCaptureError]>([])

    let fake = AudioCaptureSessionFake(
        onSample: { _ in },
        onError: { error in errors.value.append(error) }
    )

    let allCases: [AudioCaptureError] = [
        .permissionDenied("mic"),
        .permissionDenied("screen"),
        .streamFailed("init"),
        .streamFailed("runtime"),
        .unsupported,
        .streamInterrupted("disconnected"),
    ]

    for error in allCases {
        fake.injectError(error)
    }

    #expect(errors.value.count == allCases.count)
    for (idx, error) in allCases.enumerated() {
        #expect(errors.value[idx] == error)
    }
}

// MARK: - AudioCaptureSession Lifecycle Tests

@Test("stop without starting is no-op")
@MainActor
func stopWithoutStart() async {
    let session = AudioCaptureSession(
        onSample: { _ in },
        onError: { _ in },
        onFormatChange: { _, _ in }
    )
    await session.stop()
}

@Test("consecutive stops are safe")
@MainActor
func consecutiveStops() async {
    let session = AudioCaptureSession(
        onSample: { _ in },
        onError: { _ in }
    )
    await session.stop()
    await session.stop()
    await session.stop()
}

// MARK: - Test Helpers

final class ManagedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        _value = value
    }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
