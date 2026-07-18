#!/usr/bin/env swift

import Foundation

// Generates a subtle ascending two-tone success chime:
//   660Hz (80ms) → gap (10ms) → 880Hz (80ms)
//   16-bit 44100Hz mono WAV
// Total ~175ms, 5ms fade in/out on each tone.

let sampleRate: UInt32 = 44100
let totalSamples = Int(Double(sampleRate) * 0.175)
var samples = [Int16](repeating: 0, count: totalSamples)

let tone1Freq: Double = 660
let tone2Freq: Double = 880
let toneSamples = Int(Double(sampleRate) * 0.080)
let gapSamples = Int(Double(sampleRate) * 0.010)
let fadeSamples = Int(Double(sampleRate) * 0.005)

for i in 0..<toneSamples {
    let env: Double = {
        if i < fadeSamples { return Double(i) / Double(fadeSamples) }
        if i >= toneSamples - fadeSamples { return Double(toneSamples - 1 - i) / Double(fadeSamples) }
        return 1.0
    }()
    let val = sin(2.0 * .pi * tone1Freq * Double(i) / Double(sampleRate)) * env * 0.5
    samples[i] = Int16(val * Double(Int16.max))
}

let tone2Start = toneSamples + gapSamples
for i in 0..<toneSamples {
    let idx = tone2Start + i
    guard idx < totalSamples else { break }
    let env: Double = {
        if i < fadeSamples { return Double(i) / Double(fadeSamples) }
        if i >= toneSamples - fadeSamples { return Double(toneSamples - 1 - i) / Double(fadeSamples) }
        return 1.0
    }()
    let val = sin(2.0 * .pi * tone2Freq * Double(i) / Double(sampleRate)) * env * 0.5
    samples[idx] = Int16(val * Double(Int16.max))
}

func encodeWAV(samples: [Int16], sampleRate: UInt32) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = UInt32(samples.count) * UInt32(bitsPerSample / 8)
    let fileSize = 36 + dataSize

    var data = Data()
    data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
    withUnsafeBytes(of: fileSize.littleEndian) { data.append(Data($0)) }
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
    data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
    let fmtChunkSize: UInt32 = 16
    withUnsafeBytes(of: fmtChunkSize.littleEndian) { data.append(Data($0)) }
    let audioFormat: UInt16 = 1
    withUnsafeBytes(of: audioFormat.littleEndian) { data.append(Data($0)) }
    withUnsafeBytes(of: channels.littleEndian) { data.append(Data($0)) }
    withUnsafeBytes(of: sampleRate.littleEndian) { data.append(Data($0)) }
    withUnsafeBytes(of: byteRate.littleEndian) { data.append(Data($0)) }
    withUnsafeBytes(of: blockAlign.littleEndian) { data.append(Data($0)) }
    withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(Data($0)) }
    data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
    withUnsafeBytes(of: dataSize.littleEndian) { data.append(Data($0)) }
    samples.withUnsafeBytes { data.append(Data($0)) }
    return data
}

let wav = encodeWAV(samples: samples, sampleRate: sampleRate)
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/scripts/success-chime.wav"
try wav.write(to: URL(fileURLWithPath: outputPath))
print("Generated success chime: \(outputPath) (\(wav.count) bytes)")
