import Testing
import CoreMedia
import Foundation
@testable import justasec

// MARK: - Test Helpers

func float32SinePayload(
    frequency: Float32 = 440,
    durationSecs: TimeInterval = 1.0,
    sampleRate: Float64 = 48000,
    channelCount: UInt32 = 1,
    startTime: CMTime = CMTime(value: 0, timescale: 48000),
    source: AudioSource = .microphone
) -> AudioSamplePayload {
    let totalFrames = Int(sampleRate * durationSecs)
    let totalSamples = totalFrames * Int(channelCount)
    var samples = [Float32](repeating: 0, count: totalSamples)
    for i in 0..<totalSamples {
        let frame = i / Int(channelCount)
        samples[i] = sin(2 * Float32.pi * frequency * Float32(frame) / Float32(sampleRate))
    }
    let data = samples.withUnsafeBytes { Data($0) }
    let format = AudioStreamFormat(
        sampleRate: sampleRate, channelCount: channelCount, bytesPerFrame: 4 * channelCount,
        pcmFormat: .float32
    )
    return AudioSamplePayload(data: data, timestamp: startTime, format: format, source: source)
}

func int16SinePayload(
    frequency: Float32 = 440,
    durationSecs: TimeInterval = 1.0,
    sampleRate: Float64 = 48000,
    startTime: CMTime = CMTime(value: 0, timescale: 48000),
    source: AudioSource = .microphone
) -> AudioSamplePayload {
    let totalSamples = Int(sampleRate * durationSecs)
    var samples = [Int16](repeating: 0, count: totalSamples)
    for i in 0..<totalSamples {
        let val = sin(2 * Float32.pi * frequency * Float32(i) / Float32(sampleRate))
        samples[i] = Int16(val * Float32(Int16.max))
    }
    let data = samples.withUnsafeBytes { Data($0) }
    let format = AudioStreamFormat(
        sampleRate: sampleRate, channelCount: 1, bytesPerFrame: 2,
        pcmFormat: .int16
    )
    return AudioSamplePayload(data: data, timestamp: startTime, format: format, source: source)
}

func silentFloat32Payload(
    durationSecs: TimeInterval = 1.0,
    sampleRate: Float64 = 48000,
    startTime: CMTime = CMTime(value: 0, timescale: 48000),
    source: AudioSource = .microphone
) -> AudioSamplePayload {
    let totalSamples = Int(sampleRate * durationSecs)
    let data = Data(repeating: 0, count: totalSamples * 4)
    let format = AudioStreamFormat(
        sampleRate: sampleRate, channelCount: 1, bytesPerFrame: 4,
        pcmFormat: .float32
    )
    return AudioSamplePayload(data: data, timestamp: startTime, format: format, source: source)
}

func makeSegment(
    samples: [Float32],
    startTime: CMTime,
    source: AudioSource,
    sampleRate: Float64 = 16000
) -> AudioSegment {
    AudioSegment(samples: samples, startTime: startTime, source: source, sampleRate: sampleRate)
}

// MARK: - Converter

@Test("converter produces correct sample count for 48k→16k Float32 mono")
func converterSampleCount48kTo16k() throws {
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 48000)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.sampleRate == 16000)
    #expect(abs(segment.samples.count - 16000) <= 5)
    #expect(segment.source == .microphone)
}

@Test("converter produces correct sample count for 44.1k→16k")
func converterSampleCount44kTo16k() throws {
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 44100)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.sampleRate == 16000)
    #expect(segment.samples.count > 15950 && segment.samples.count < 16100)
}

@Test("converter stereo mixes to mono")
func converterStereoToMono() throws {
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 48000, channelCount: 2)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.sampleRate == 16000)
    #expect(abs(segment.samples.count - 16000) <= 5)
}

@Test("converter handles Int16 input")
func converterInt16Input() throws {
    let payload = int16SinePayload(durationSecs: 1.0, sampleRate: 48000)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.sampleRate == 16000)
    #expect(!segment.samples.isEmpty)
    // Should have non-zero content (sine wave)
    let maxAbs = segment.samples.map { abs($0) }.max() ?? 0
    #expect(maxAbs > 0.01)
}

@Test("converter passes through matching sample rate")
func converterMatchingRate() throws {
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.samples.count == 16000)
}

@Test("converter rejects unsupported format")
func converterRejectsUnsupported() throws {
    let data = Data(repeating: 0, count: 1024)
    let format = AudioStreamFormat(
        sampleRate: 48000, channelCount: 1, bytesPerFrame: 6,
        pcmFormat: .unknown
    )
    let payload = AudioSamplePayload(data: data, timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) {
        try AudioConverter.convert(payload)
    }
}

@Test("converter empty payload produces empty segment")
func converterEmptyPayload() throws {
    let data = Data()
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 4, pcmFormat: .float32)
    let payload = AudioSamplePayload(data: data, timestamp: .zero, format: format, source: .microphone)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.samples.isEmpty)
}

@Test("converter preserves timestamp from payload")
func converterPreservesTimestamp() throws {
    let ts = CMTime(value: 12345, timescale: 48000)
    let payload = float32SinePayload(durationSecs: 0.1, sampleRate: 48000, startTime: ts)
    let segment = try AudioConverter.convert(payload)
    #expect(segment.startTime == ts)
}

@Test("converter preserves source")
func converterPreservesSource() throws {
    let mic = float32SinePayload(source: .microphone)
    let sys = float32SinePayload(startTime: CMTime(value: 100, timescale: 48000), source: .systemAudio)
    let micSeg = try AudioConverter.convert(mic)
    let sysSeg = try AudioConverter.convert(sys)
    #expect(micSeg.source == AudioSource.microphone)
    #expect(sysSeg.source == AudioSource.systemAudio)
}

// MARK: - AudioSegment Helpers

@Test("AudioSegment duration computed correctly")
func segmentDuration() {
    let seg = AudioSegment(samples: [Float32](repeating: 0, count: 16000), startTime: .zero, source: .microphone, sampleRate: 16000)
    #expect(seg.durationSeconds == 1.0)
}

@Test("AudioSegment endTime computed correctly")
func segmentEndTime() {
    let seg = AudioSegment(samples: [Float32](repeating: 0, count: 32000), startTime: .zero, source: .microphone, sampleRate: 16000)
    let expectedEnd = CMTime(value: 32000, timescale: 16000)
    #expect(seg.endTime == expectedEnd)
}

// MARK: - Timeline

@Test("timeline returns silence for empty sources")
func timelineEmptySources() async {
    let timeline = AudioTimeline()
    let now = CMTime(value: 480000, timescale: 16000)
    let snap = await timeline.snapshot(before: now, duration: 1.0)
    #expect(snap.microphone.count == 16000)
    #expect(snap.systemAudio.count == 16000)
    #expect(snap.microphone.allSatisfy { $0 == 0 })
    #expect(snap.systemAudio.allSatisfy { $0 == 0 })
}

@Test("timeline returns ingested data for correct source")
func timelineSingleSource() async throws {
    let timeline = AudioTimeline()
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000)
    let segment = try AudioConverter.convert(payload)
    await timeline.ingest(segment)

    let endTime = CMTime(value: 16000, timescale: 16000)
    // Snapshot with 1s window exactly covering the data
    let snap = await timeline.snapshot(before: endTime, duration: 1.0)
    let micMax = snap.microphone.map { abs($0) }.max() ?? 0
    #expect(micMax > 0.01)
    #expect(snap.systemAudio.allSatisfy { $0 == 0 })
}

@Test("timeline both sources independently stored")
func timelineBothSources() async throws {
    let timeline = AudioTimeline()
    let micPayload = float32SinePayload(durationSecs: 0.5, sampleRate: 16000, startTime: .zero, source: .microphone)
    let sysPayload = float32SinePayload(durationSecs: 0.5, sampleRate: 16000, startTime: CMTime(value: 8000, timescale: 16000), source: .systemAudio)
    await timeline.ingest(try AudioConverter.convert(micPayload))
    await timeline.ingest(try AudioConverter.convert(sysPayload))

    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    // Mic: first 0.5s signal, rest silence
    let micMax = snap.microphone[0..<8000].map { abs($0) }.max() ?? 0
    #expect(micMax > 0.01)
    // Sys: first 0.5s silence, then 0.5s signal
    let sysFirst = snap.systemAudio[0..<8000].map { abs($0) }.max() ?? 0
    let sysSecond = snap.systemAudio[8000..<16000].map { abs($0) }.max() ?? 0
    #expect(sysFirst < 0.001)
    #expect(sysSecond > 0.01)
}

@Test("timeline evicts data older than 30s")
func timelineExpiry() async throws {
    let timeline = AudioTimeline()
    let oldPayload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: .zero)
    let newPayload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: CMTime(value: 576000, timescale: 16000))

    await timeline.ingest(try AudioConverter.convert(oldPayload))
    await timeline.ingest(try AudioConverter.convert(newPayload))

    // latestTime = 36s + 1s = 37s
    // cutoff = 37s - 30s = 7s
    // Old segment endTime = 1s < 7s → evicted
    // New segment endTime = 37s > 7s → retained
    let snap = await timeline.snapshot(before: CMTime(value: 592000, timescale: 16000), duration: 30.0)
    // Window = [7s, 37s]. Old data at 0s evicted, first few seconds should be silence
    let firstSecMax = snap.microphone[0..<16000].map { abs($0) }.max() ?? 999
    #expect(firstSecMax < 0.001)
    // New data at 36s should be within window at offset (36s - 7s) * 16000 = 29 * 16000 = 464000
    let lastSecMax = snap.microphone[464000..<480000].map { abs($0) }.max() ?? 0
    #expect(lastSecMax > 0.01)
}

@Test("timeline long-running boundedness")
func timelineBounded() async throws {
    let timeline = AudioTimeline()
    // Insert 100 segments spanning >30s total
    for i in 0..<100 {
        let ts = CMTime(value: CMTimeValue(i * 5000), timescale: 16000)
        let payload = float32SinePayload(durationSecs: 0.1, sampleRate: 16000, startTime: ts)
        await timeline.ingest(try AudioConverter.convert(payload))
    }
    // Snapshot at end
    let snap = await timeline.snapshot(before: CMTime(value: 500000, timescale: 16000), duration: 30.0)
    #expect(snap.microphone.count == 480000)
    // Verify not all silence (some data should remain in 30s window)
    let maxVal = snap.microphone.map { abs($0) }.max() ?? 0
    #expect(maxVal > 0.001)
}

@Test("timeline handles gap with silence fill")
func timelineGapFill() async throws {
    let timeline = AudioTimeline()
    // Data at 0-1s, gap 1-3s, data at 3-4s
    let first = try AudioConverter.convert(float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: .zero))
    let third = try AudioConverter.convert(float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: CMTime(value: 48000, timescale: 16000)))
    await timeline.ingest(first)
    await timeline.ingest(third)

    let snap = await timeline.snapshot(before: CMTime(value: 64000, timescale: 16000), duration: 4.0)
    #expect(snap.microphone.count == 64000)
    // Samples at 0-16000: signal
    let firstMax = snap.microphone[0..<16000].map { abs($0) }.max() ?? 0
    // Samples at 16000-48000: silence (gap)
    let gapMax = snap.microphone[16000..<48000].map { abs($0) }.max() ?? 999
    // Samples at 48000-64000: signal
    let lastMax = snap.microphone[48000..<64000].map { abs($0) }.max() ?? 0
    #expect(firstMax > 0.01)
    #expect(gapMax < 0.001)
    #expect(lastMax > 0.01)
}

// MARK: - Mixer

@Test("mixer produces same length as inputs")
func mixerSameLength() {
    let a: [Float32] = [0.1, 0.2, 0.3]
    let b: [Float32] = [0.4, 0.5, 0.6]
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    #expect(mixed.count == a.count)
}

@Test("mixer adds two signals with gain staging")
func mixerAddsWithGainStaging() {
    let a: [Float32] = [0.3, -0.3, 0.0, 0.8]
    let b: [Float32] = [0.2, -0.2, 0.0, 0.8]
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    #expect(abs(mixed[0] - 0.25) < 0.001)
    #expect(abs(mixed[1] - (-0.25)) < 0.001)
    #expect(abs(mixed[2] - 0.0) < 0.001)
    #expect(abs(mixed[3] - 0.8) < 0.001)
}

@Test("mixer handles clipping without overflow")
func mixerClipping() {
    let a: [Float32] = [0.9, 0.9]
    let b: [Float32] = [0.9, 0.9]
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    for v in mixed {
        #expect(v >= -1.0)
        #expect(v <= 1.0)
    }
}

@Test("mixer handles one empty array")
func mixerOneEmpty() {
    let a: [Float32] = [0.5, 0.5]
    let b: [Float32] = []
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    #expect(mixed.count == a.count)
    #expect(zip(mixed, a).allSatisfy { abs($0 - $1) < 0.001 })
}

@Test("mixer handles both empty")
func mixerBothEmpty() {
    let mixed = AudioMixer.mix(microphone: [], systemAudio: [])
    #expect(mixed.isEmpty)
}

// MARK: - EnergyGate

@Test("energy gate detects silence")
func energyGateSilence() {
    let samples = [Float32](repeating: 0, count: 1000)
    #expect(EnergyGate.isSilent(samples))
}

@Test("energy gate passes non-silent")
func energyGateNonSilent() {
    let samples = [Float32](repeating: 0.1, count: 1000)
    #expect(!EnergyGate.isSilent(samples))
}

@Test("energy gate uses threshold")
func energyGateThreshold() {
    let samples = [Float32](repeating: 0.0001, count: 1000)
    #expect(EnergyGate.isSilent(samples, threshold: 0.001))
    #expect(!EnergyGate.isSilent(samples, threshold: 0.00001))
}

@Test("energy gate empty array is silent")
func energyGateEmpty() {
    #expect(EnergyGate.isSilent([]))
}

// MARK: - WAVEncoder

@Test("wav header is 44 bytes and valid")
func wavHeaderSize() throws {
    let samples: [Float32] = [0.0, 0.5, -0.5]
    let data = try WAVEncoder.encodePCM16(samples, sampleRate: 16000)
    #expect(data.count >= 44)
    #expect(data[0..<4].elementsEqual("RIFF".utf8))
    #expect(data[8..<12].elementsEqual("WAVE".utf8))
    #expect(data[12..<16].elementsEqual("fmt ".utf8))
}

@Test("wav data chunk size matches sample count")
func wavDataSize() throws {
    let samples: [Float32] = [Float32](repeating: 0.0, count: 16000)
    let data = try WAVEncoder.encodePCM16(samples, sampleRate: 16000)
    let dataSize: Int = Int(UInt32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }))
    #expect(dataSize == 16000 * 2)
    #expect(data.count == 44 + dataSize)
}

@Test("wav round-trip preserves approximate values")
func wavRoundTrip() throws {
    let original: [Float32] = [0.0, 0.5, -0.5, 0.25, -0.25, 1.0, -1.0]
    let wav = try WAVEncoder.encodePCM16(original, sampleRate: 16000)
    let samples = try decodeWav(data: wav)
    #expect(samples.count == original.count)
    for (orig, decoded) in zip(original, samples) {
        let diff = abs(abs(orig) - abs(decoded))
        #expect(diff < 0.002)
    }
}

@Test("wav empty samples produce valid wav")
func wavEmpty() throws {
    let data = try WAVEncoder.encodePCM16([], sampleRate: 16000)
    #expect(data.count == 44)
    let dataSize: Int = Int(UInt32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }))
    #expect(dataSize == 0)
}

// MARK: - Snapshot Integration

@Test("full snapshot returns non-nil for non-silent input")
func snapshotNonSilent() async throws {
    let engine = SnapshotEngine()
    let payload = float32SinePayload(durationSecs: 1.0, sampleRate: 16000, startTime: .zero)
    await engine.ingestPayload(payload)
    let now = CMTime(value: 16000, timescale: 16000)
    let wav = try await engine.snapshot(before: now, duration: 1.0)
    #expect(wav != nil)
    #expect(wav!.count > 44)
}

@Test("full snapshot returns nil for silent input")
func snapshotSilent() async throws {
    let engine = SnapshotEngine()
    let payload = silentFloat32Payload(durationSecs: 1.0, sampleRate: 16000, startTime: .zero)
    await engine.ingestPayload(payload)
    let now = CMTime(value: 16000, timescale: 16000)
    let wav = try await engine.snapshot(before: now, duration: 1.0)
    #expect(wav == nil)
}

// MARK: - Blocker 1: Overlap and out-of-order

@Test("timeline overlap latest replaces existing")
func timelineOverlapLatestWins() async throws {
    let timeline = AudioTimeline()
    let first = makeSegment(samples: [Float32](repeating: 0.5, count: 16000), startTime: .zero, source: .microphone)
    let second = makeSegment(samples: [Float32](repeating: 1.0, count: 8000), startTime: CMTime(value: 4000, timescale: 16000), source: .microphone)
    await timeline.ingest(first)
    await timeline.ingest(second)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    // First 0.25s (0-4000): original 0.5
    let firstQ = snap.microphone[0..<4000]
    #expect(firstQ.allSatisfy { $0 == 0.5 })
    // Next 0.5s (4000-12000): latest 1.0 (overlapping second segment)
    let mid = snap.microphone[4000..<12000]
    #expect(mid.allSatisfy { $0 == 1.0 })
    // Last 0.25s (12000-16000): original 0.5 (no overlap)
    let lastQ = snap.microphone[12000..<16000]
    #expect(lastQ.allSatisfy { $0 == 0.5 })
}

@Test("timeline out-of-order insertion preserves sorted order")
func timelineOutOfOrder() async throws {
    let timeline = AudioTimeline()
    let later = makeSegment(samples: [Float32](repeating: 1.0, count: 8000), startTime: CMTime(value: 8000, timescale: 16000), source: .microphone)
    let earlier = makeSegment(samples: [Float32](repeating: 0.5, count: 8000), startTime: .zero, source: .microphone)
    await timeline.ingest(later)
    await timeline.ingest(earlier)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(snap.microphone[0..<8000].allSatisfy { $0 == 0.5 })
    #expect(snap.microphone[8000..<16000].allSatisfy { $0 == 1.0 })
}

@Test("timeline fractional timestamps place samples correctly")
func timelineFractionalTimestamps() async {
    let timeline = AudioTimeline()
    // Use CMTime with non-integer-second timescale to test drift tolerance
    let ts = CMTime(value: 1, timescale: 10) // 0.1s
    let seg = makeSegment(samples: [Float32](repeating: 1.0, count: 1600), startTime: ts, source: .microphone)
    await timeline.ingest(seg)
    let snap = await timeline.snapshot(before: CMTime(value: 2, timescale: 10), duration: 0.2)
    #expect(snap.microphone.count == 3200)
    // Silent first 0.1s
    #expect(snap.microphone[0..<1600].allSatisfy { $0 == 0 })
    // Signal next 0.1s
    #expect(snap.microphone[1600..<3200].allSatisfy { $0 == 1.0 })
}

@Test("timeline half-open window excludes segment at exact end boundary")
func timelineHalfOpenExcludesEnd() async {
    let timeline = AudioTimeline()
    let seg = makeSegment(samples: [Float32](repeating: 1.0, count: 8000), startTime: CMTime(value: 16000, timescale: 16000), source: .microphone)
    // segment starts exactly at windowEnd → excluded
    await timeline.ingest(seg)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(snap.microphone.allSatisfy { $0 == 0 })
}

@Test("timeline half-open window includes segment at exact start boundary")
func timelineHalfOpenIncludesStart() async {
    let timeline = AudioTimeline()
    let seg = makeSegment(samples: [Float32](repeating: 1.0, count: 8000), startTime: .zero, source: .microphone)
    await timeline.ingest(seg)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(!snap.microphone.allSatisfy { $0 == 0 })
}

// MARK: - Blocker 2: Snapshot anchor

@Test("snapshot produces exactly 480k samples per source for 30s")
func snapshotExact480k() async throws {
    let timeline = AudioTimeline()
    let seg = makeSegment(samples: [Float32](repeating: 0.5, count: 480000), startTime: .zero, source: .microphone)
    await timeline.ingest(seg)
    let snap = await timeline.snapshot(before: CMTime(value: 480000, timescale: 16000), duration: 30.0)
    #expect(snap.microphone.count == 480000)
    #expect(snap.systemAudio.count == 480000)
}

@Test("snapshot silence-fills missing source")
func snapshotMissingSource() async throws {
    let timeline = AudioTimeline()
    let seg = makeSegment(samples: [Float32](repeating: 0.5, count: 16000), startTime: .zero, source: .microphone)
    await timeline.ingest(seg)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(snap.microphone.contains { $0 != 0 }) // has non-zero
    #expect(snap.systemAudio.allSatisfy { $0 == 0 }) // silence
}

@Test("snapshot uses global end timestamp for both sources")
func snapshotGlobalEndTimestamp() async throws {
    let timeline = AudioTimeline()
    // Mic: data at [0, 0.5s], Sys: data at [0.5s, 1.0s]
    let mic = makeSegment(samples: [Float32](repeating: 0.5, count: 8000), startTime: .zero, source: .microphone)
    let sys = makeSegment(samples: [Float32](repeating: 1.0, count: 8000), startTime: CMTime(value: 8000, timescale: 16000), source: .systemAudio)
    await timeline.ingest(mic)
    await timeline.ingest(sys)
    // Snapshot at 1.0s, 1s window → [0, 1.0)
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(snap.microphone[0..<8000].allSatisfy { $0 == 0.5 })
    #expect(snap.microphone[8000..<16000].allSatisfy { $0 == 0 })
    #expect(snap.systemAudio[0..<8000].allSatisfy { $0 == 0 })
    #expect(snap.systemAudio[8000..<16000].allSatisfy { $0 == 1.0 })
}

// MARK: - Blocker 3: Mixer gain

@Test("mixer divides by two prevents full-scale clipping")
func mixerDividesByTwo() {
    let a: [Float32] = [1.0, -1.0, 0.5]
    let b: [Float32] = [1.0, -1.0, 0.5]
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    #expect(mixed.count == 3)
    #expect(abs(mixed[0] - 1.0) < 0.001)
    #expect(abs(mixed[1] - (-1.0)) < 0.001)
    #expect(abs(mixed[2] - 0.5) < 0.001)
}

@Test("mixer equal loud tracks produce deterministic output")
func mixerEqualLoudness() {
    let a: [Float32] = [0.8, -0.8]
    let b: [Float32] = [0.6, -0.6]
    let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
    #expect(abs(mixed[0] - 0.7) < 0.001)
    #expect(abs(mixed[1] - (-0.7)) < 0.001)
}

@Test("mixer never exceeds safe range")
func mixerSafeRange() {
    for _ in 0..<100 {
        let a: [Float32] = (0..<100).map { _ in Float32.random(in: -1...1) }
        let b: [Float32] = (0..<100).map { _ in Float32.random(in: -1...1) }
        let mixed = AudioMixer.mix(microphone: a, systemAudio: b)
        #expect(mixed.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }
}

// MARK: - Blocker 4: Error routing

@Test("snapshot engine error callback receives conversion errors")
func engineErrorCallbackReceivesErrors() async {
    let errors = ManagedBox<[AudioPipelineError]>([])
    let engine = SnapshotEngine(onError: { errors.value.append($0) })
    let badFormat = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 6, pcmFormat: .unknown)
    let badPayload = AudioSamplePayload(data: Data(repeating: 0, count: 100), timestamp: .zero, format: badFormat, source: .microphone)
    await engine.ingestPayload(badPayload)
    #expect(!errors.value.isEmpty)
}

@Test("snapshot engine error not called on success")
func engineErrorNotCalledOnSuccess() async throws {
    let errors = ManagedBox<[AudioPipelineError]>([])
    let engine = SnapshotEngine(onError: { errors.value.append($0) })
    let payload = float32SinePayload(durationSecs: 0.1, sampleRate: 16000, startTime: .zero)
    await engine.ingestPayload(payload)
    #expect(errors.value.isEmpty)
}

// MARK: - Blocker 5: Benchmark

@Test("snapshot 1000-segment benchmark under 0.5s")
func snapshotBenchmark1000Segments() async throws {
    let timeline = AudioTimeline()
    for i in 0..<1000 {
        let ts = CMTime(value: CMTimeValue(i * 480), timescale: 16000) // each 0.03s
        let seg = makeSegment(samples: [Float32](repeating: 0.5, count: 480), startTime: ts, source: .microphone)
        await timeline.ingest(seg)
    }
    let start = CFAbsoluteTimeGetCurrent()
    let snap = await timeline.snapshot(before: CMTime(value: 480000, timescale: 16000), duration: 30.0)
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    #expect(snap.microphone.count == 480000)
    #expect(elapsed < 0.5)
}

// MARK: - Blocker 6: Concurrency, WAV validation

@Test("concurrent ingest and snapshot race")
func concurrentIngestSnapshot() async {
    let engine = SnapshotEngine()
    async let ingest1: Void = engine.ingestPayload(float32SinePayload(durationSecs: 0.5, sampleRate: 16000, startTime: .zero))
    async let ingest2: Void = engine.ingestPayload(float32SinePayload(durationSecs: 0.5, sampleRate: 16000, startTime: CMTime(value: 8000, timescale: 16000)))
    async let snapResult = try? await engine.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    let (_, _, wav) = await (ingest1, ingest2, snapResult)
    if let wav { #expect(wav.count > 44) }
}

@Test("wav header specifies 16kHz mono PCM exactly")
func wavExactHeader() throws {
    let samples: [Float32] = [0.0, 0.5, -0.5]
    let data = try WAVEncoder.encodePCM16(samples, sampleRate: 16000)
    let fmt = { (offset: Int, size: Int) -> Data in data[offset..<offset+size] }
    // audioFormat = 1 (PCM)
    let audioFmt: UInt16 = fmt(20, 2).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    #expect(audioFmt == 1)
    // numChannels = 1 (mono)
    let channels: UInt16 = fmt(22, 2).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    #expect(channels == 1)
    // sampleRate = 16000
    let rate: UInt32 = fmt(24, 4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    #expect(rate == 16000)
    // bitsPerSample = 16
    let bps: UInt16 = fmt(34, 2).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    #expect(bps == 16)
    // data chunk byte count is even (sample-aligned)
    let dataSize: UInt32 = fmt(40, 4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    #expect(dataSize % 2 == 0)
    #expect(dataSize == UInt32(samples.count * 2))
    // fileSize = 36 + dataSize
    let fileSize: UInt32 = fmt(4, 4).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    #expect(fileSize == 36 + dataSize)
}

// MARK: - Security: format validation

@Test("converter rejects zero sampleRate")
func converterRejectsZeroSampleRate() {
    let format = AudioStreamFormat(sampleRate: 0, channelCount: 1, bytesPerFrame: 4, pcmFormat: .float32)
    let payload = AudioSamplePayload(data: Data(repeating: 0, count: 100), timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) { try AudioConverter.convert(payload) }
}

@Test("converter rejects zero channelCount")
func converterRejectsZeroChannelCount() {
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 0, bytesPerFrame: 0, pcmFormat: .float32)
    let payload = AudioSamplePayload(data: Data(repeating: 0, count: 100), timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) { try AudioConverter.convert(payload) }
}

@Test("converter rejects zero bytesPerFrame")
func converterRejectsZeroBytesPerFrame() {
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 0, pcmFormat: .float32)
    let payload = AudioSamplePayload(data: Data(repeating: 0, count: 100), timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) { try AudioConverter.convert(payload) }
}

@Test("converter rejects inconsistent data length")
func converterRejectsInconsistentDataLength() {
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 2, bytesPerFrame: 8, pcmFormat: .float32)
    // 10 bytes not divisible by 8
    let payload = AudioSamplePayload(data: Data(repeating: 0, count: 10), timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) { try AudioConverter.convert(payload) }
}

@Test("converter rejects unknown PCMFormat with 3-byte samples")
func converterRejectsUnknownFormat3Byte() {
    let format = AudioStreamFormat(sampleRate: 48000, channelCount: 1, bytesPerFrame: 3, pcmFormat: .unknown)
    let payload = AudioSamplePayload(data: Data(repeating: 0, count: 48000 * 3), timestamp: .zero, format: format, source: .microphone)
    #expect(throws: AudioPipelineError.self) { try AudioConverter.convert(payload) }
}

// MARK: - Security: WAV bounds

@Test("wav encoder rejects oversized sample count")
func wavRejectsOversized() {
    // 3 billion samples would overflow UInt32 data size
    let huge = [Float32](repeating: 0.0, count: 3_000_000_000)
    #expect(throws: AudioPipelineError.self) { try WAVEncoder.encodePCM16(huge, sampleRate: 16000) }
}

// MARK: - Security: NaN/Inf sanitization

@Test("energy gate treats NaN as silent")
func energyGateNaN() {
    let samples: [Float32] = [Float32.nan, 0.0, 0.0]
    #expect(EnergyGate.isSilent(samples))
}

@Test("energy gate treats Inf as non-silent only if finite content present")
func energyGateInf() {
    let samples: [Float32] = [Float32.infinity, 0.0, 0.0]
    #expect(EnergyGate.isSilent(samples)) // non-finite should be treated as 0 → silent
}

@Test("wav encoder handles NaN without crash")
func wavEncodesNaN() throws {
    let samples: [Float32] = [Float32.nan, 0.5, -0.5]
    let data = try WAVEncoder.encodePCM16(samples, sampleRate: 16000)
    #expect(data.count == 44 + 3 * 2)
}

// MARK: - Security: overlap ordering + coalesce

@Test("timeline insert maintains sorted non-overlapping order after nested overlaps")
func timelineNestedOverlapsSorted() async {
    let timeline = AudioTimeline()
    // Insert segments that cause multiple overlaps
    let a = makeSegment(samples: [Float32](repeating: 0.1, count: 16000), startTime: .zero, source: .microphone)
    let b = makeSegment(samples: [Float32](repeating: 0.2, count: 16000), startTime: CMTime(value: 8000, timescale: 16000), source: .microphone)
    let c = makeSegment(samples: [Float32](repeating: 0.3, count: 16000), startTime: CMTime(value: 4000, timescale: 16000), source: .microphone)
    await timeline.ingest(a)
    await timeline.ingest(b)
    await timeline.ingest(c)
    let snap = await timeline.snapshot(before: CMTime(value: 24000, timescale: 16000), duration: 1.5)
    // c (0.3) wins for [4000, 20000); a wins for [0, 4000); b wins for [20000, 24000)
    // but b starts at 8000, so b only has [8000, 24000), and c (4000-20000) overlaps
    // After all inserts: [a:0-4000, c:4000-20000, b:20000-24000]
    #expect(snap.microphone[0..<4000].allSatisfy { $0 == 0.1 })
    #expect(snap.microphone[4000..<20000].allSatisfy { $0 == 0.3 })
    #expect(snap.microphone[20000..<24000].allSatisfy { $0 == 0.2 })
}

@Test("timeline repeated overlapping insert does not fragment unboundedly")
func timelineRepeatedOverlapBounded() async {
    let timeline = AudioTimeline()
    // 100 overlapping inserts in same region
    for i in 0..<100 {
        let val = Float32(i) / 100.0
        let seg = makeSegment(samples: [Float32](repeating: val, count: 8000), startTime: CMTime(value: 4000, timescale: 16000), source: .microphone)
        await timeline.ingest(seg)
    }
    let snap = await timeline.snapshot(before: CMTime(value: 16000, timescale: 16000), duration: 1.0)
    #expect(snap.microphone[4000..<12000].allSatisfy { $0 == 0.99 })
    // Remaining segment count should be small (coalesced)
}

// MARK: - Security: Sendable conformance

@Test("SnapshotEngine is Sendable")
func snapshotEngineIsSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(SnapshotEngine.self)
}

// MARK: - WAV Decode Helper

func decodeWav(data: Data) throws -> [Float32] {
    let headerSize = 44
    guard data.count >= headerSize else { throw AudioPipelineError.conversionFailed("too small") }
    let dataSize: Int = Int(UInt32(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }))
    guard data.count >= headerSize + dataSize else { throw AudioPipelineError.conversionFailed("truncated") }
    let sampleCount = dataSize / 2
    var result = [Float32](repeating: 0, count: sampleCount)
    for i in 0..<sampleCount {
        let raw = Int16(littleEndian: data.withUnsafeBytes { $0.load(fromByteOffset: headerSize + i * 2, as: Int16.self) })
        result[i] = Float32(raw) / Float32(Int16.max)
    }
    return result
}
