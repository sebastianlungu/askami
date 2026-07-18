import Foundation
import CoreMedia
@preconcurrency import AVFoundation
import Accelerate

// MARK: - Error

public enum AudioPipelineError: Error, Sendable, Equatable {
    case unsupportedFormat(String)
    case conversionFailed(String)
    case overflow(String)
}

// MARK: - Converted Segment

public struct AudioSegment: Sendable, Equatable {
    public let samples: [Float32]
    public let startTime: CMTime
    public let source: AudioSource
    public let sampleRate: Float64

    public init(samples: [Float32], startTime: CMTime, source: AudioSource, sampleRate: Float64) {
        self.samples = samples
        self.startTime = startTime
        self.source = source
        self.sampleRate = sampleRate
    }

    public var durationSeconds: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(samples.count) / sampleRate
    }

    public var endTime: CMTime {
        let duration = CMTime(value: CMTimeValue(samples.count), timescale: CMTimeScale(sampleRate))
        return CMTimeAdd(startTime, duration)
    }
}

// MARK: - Converter

public struct AudioConverter {
    public static func convert(_ payload: AudioSamplePayload) throws -> AudioSegment {
        try validate(payload)
        let bpf = Int(payload.format.bytesPerFrame)
        let totalFrames = payload.data.count / bpf
        guard totalFrames > 0 else {
            return AudioSegment(samples: [], startTime: payload.timestamp, source: payload.source, sampleRate: 16000)
        }
        let floatSamples = sanitize(try decodeSamples(payload, totalFrames: totalFrames))
        let mono = mixdownToMono(floatSamples, totalFrames: totalFrames, channels: Int(payload.format.channelCount))
        let resampled = try resample(mono, from: payload.format.sampleRate, to: 16000)
        return AudioSegment(samples: resampled, startTime: payload.timestamp, source: payload.source, sampleRate: 16000)
    }

    private static func validate(_ payload: AudioSamplePayload) throws {
        guard payload.format.sampleRate > 0 else { throw AudioPipelineError.unsupportedFormat("zero sampleRate") }
        guard payload.format.channelCount > 0 else { throw AudioPipelineError.unsupportedFormat("zero channelCount") }
        guard payload.format.bytesPerFrame > 0 else { throw AudioPipelineError.unsupportedFormat("zero bytesPerFrame") }
        guard payload.format.bytesPerSample > 0 else { throw AudioPipelineError.unsupportedFormat("invalid bytesPerSample") }
        let bpf = Int(payload.format.bytesPerFrame)
        guard payload.data.count % bpf == 0 else {
            throw AudioPipelineError.unsupportedFormat("data length \(payload.data.count) not divisible by bytesPerFrame \(bpf)")
        }
    }

    private static func decodeSamples(_ payload: AudioSamplePayload, totalFrames: Int) throws -> [Float32] {
        let totalChannels = Int(payload.format.channelCount)
        let bytesPerSample = payload.format.bytesPerSample
        var result = [Float32](repeating: 0, count: totalFrames * totalChannels)
        if payload.format.isFloat && bytesPerSample == 4 {
            payload.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let floats = ptr.bindMemory(to: Float32.self)
                let copyCount = min(floats.count, result.count)
                for i in 0..<copyCount { result[i] = floats[i] }
            }
        } else if !payload.format.isFloat && bytesPerSample == 2 {
            payload.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let ints = ptr.bindMemory(to: Int16.self)
                let copyCount = min(ints.count, result.count)
                for i in 0..<copyCount { result[i] = Float32(ints[i]) / Float32(Int16.max) }
            }
        } else {
            throw AudioPipelineError.unsupportedFormat("float=\(payload.format.isFloat) bytesPerSample=\(bytesPerSample)")
        }
        return result
    }

    private static func sanitize(_ samples: [Float32]) -> [Float32] {
        var s = samples
        for i in s.indices { if !s[i].isFinite { s[i] = 0 } }
        return s
    }

    private static func mixdownToMono(_ samples: [Float32], totalFrames: Int, channels: Int) -> [Float32] {
        guard channels > 1 else { return samples }
        return (0..<totalFrames).map { f in
            var sum: Float32 = 0
            for c in 0..<channels { sum += samples[f * channels + c] }
            return sum / Float32(channels)
        }
    }

    private static func resample(_ input: [Float32], from: Float64, to: Float64) throws -> [Float32] {
        guard from != to else { return input }
        guard from > 0, to > 0 else { throw AudioPipelineError.conversionFailed("invalid sample rate") }
        guard !input.isEmpty else { return [] }
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false)!
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioPipelineError.conversionFailed("cannot create converter")
        }
        let inputFrameCount = AVAudioFrameCount(input.count)
        let outputCapacity = AVAudioFrameCount(Double(input.count) * to / from) + 1
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            throw AudioPipelineError.conversionFailed("cannot create input buffer")
        }
        inputBuffer.frameLength = inputFrameCount
        let inputCh = inputBuffer.floatChannelData!
        memcpy(inputCh[0], input, input.count * MemoryLayout<Float32>.stride)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AudioPipelineError.conversionFailed("cannot create output buffer")
        }
        var convError: NSError?
        let providedLock = OSAllocatedUnfairLock(initialState: false)
        let status = converter.convert(to: outputBuffer, error: &convError) { _, outStatus in
            let alreadyProvided = providedLock.withLock { $0 }
            guard !alreadyProvided else { outStatus.pointee = .endOfStream; return nil }
            providedLock.withLock { $0 = true }
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error else {
            throw AudioPipelineError.conversionFailed("conversion: \(convError?.localizedDescription ?? "unknown")")
        }
        let frameLength = Int(outputBuffer.frameLength)
        let outputCh = outputBuffer.floatChannelData!
        return Array(UnsafeBufferPointer(start: outputCh[0], count: frameLength))
    }
}

// MARK: - Mixer

public struct AudioMixer {
    public static func mix(microphone mic: [Float32], systemAudio sys: [Float32]) -> [Float32] {
        guard !mic.isEmpty else { return sys }
        guard !sys.isEmpty else { return mic }
        let count = max(mic.count, sys.count)
        return (0..<count).map { i in
            let a = i < mic.count ? (mic[i].isFinite ? mic[i] : 0) : 0
            let b = i < sys.count ? (sys[i].isFinite ? sys[i] : 0) : 0
            return (a + b) * 0.5
        }
    }
}

// MARK: - Energy Gate

public struct EnergyGate {
    public static func isSilent(_ samples: [Float32], threshold: Float32 = 1e-4) -> Bool {
        guard !samples.isEmpty else { return true }
        var finite = samples
        for i in finite.indices {
            if !finite[i].isFinite { finite[i] = 0 }
        }
        var sumSq: Float32 = 0
        vDSP_svesq(finite, 1, &sumSq, vDSP_Length(finite.count))
        let rms = sqrt(sumSq / Float32(finite.count))
        return rms < threshold
    }
}

// MARK: - WAV Encoder

public struct WAVEncoder {
    public static func encodePCM16(_ samples: [Float32], sampleRate: Int) throws -> Data {
        let dataBytes = try computeDataByteCount(samples.count)
        var wav = Data(capacity: 44 + dataBytes)
        writeHeader(to: &wav, sampleRate: sampleRate, dataBytes: UInt32(dataBytes))
        writeSamples(samples, to: &wav)
        return wav
    }

    private static func computeDataByteCount(_ count: Int) throws -> Int {
        let bps = 2
        let (dataBytes, overflow) = count.multipliedReportingOverflow(by: bps)
        guard !overflow else { throw AudioPipelineError.overflow("WAV data byte count overflow") }
        guard dataBytes <= Int(UInt32.max) else { throw AudioPipelineError.overflow("WAV data size exceeds 32-bit RIFF limit") }
        return dataBytes
    }

    private static func writeHeader(to wav: inout Data, sampleRate: Int, dataBytes: UInt32) {
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = UInt16(numChannels) * UInt16(bitsPerSample) / 8
        let fileSize = 36 + dataBytes
        wav.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: fileSize.littleEndian) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        let fmtSize: UInt32 = 16
        withUnsafeBytes(of: fmtSize.littleEndian) { wav.append(contentsOf: $0) }
        let audioFormat: UInt16 = 1
        withUnsafeBytes(of: audioFormat.littleEndian) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: numChannels.littleEndian) { wav.append(contentsOf: $0) }
        let sr = UInt32(sampleRate).littleEndian
        withUnsafeBytes(of: sr) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataBytes.littleEndian) { wav.append(contentsOf: $0) }
    }

    private static func writeSamples(_ samples: [Float32], to wav: inout Data) {
        for s in samples {
            let clamped = s.isFinite ? s : 0
            var intVal = Int16(clamping: Int(clamped * Float32(Int16.max)))
            withUnsafeBytes(of: &intVal) { wav.append(contentsOf: $0) }
        }
    }
}
