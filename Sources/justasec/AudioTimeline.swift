import Foundation
import CoreMedia

public actor AudioTimeline {
    public static let retentionDuration: TimeInterval = 30.0
    public static let targetSampleRate: Float64 = 16000
    public static let targetSampleCount: Int = Int(retentionDuration * targetSampleRate)

    private var microphone: [AudioSegment] = []
    private var systemAudio: [AudioSegment] = []
    private var latestTime: CMTime?

    public init() {}

    public func ingest(_ segment: AudioSegment) {
        switch segment.source {
        case .microphone: insert(segment, into: &microphone)
        case .systemAudio: insert(segment, into: &systemAudio)
        }

        let segEnd = segment.endTime
        if let latest = latestTime {
            if CMTimeCompare(segEnd, latest) > 0 { latestTime = segEnd }
        } else {
            latestTime = segEnd
        }
        if let latest = latestTime { evict(before: latest) }
    }

    public func snapshot(
        before timestamp: CMTime, duration: TimeInterval
    ) -> (microphone: [Float32], systemAudio: [Float32]) {
        let windowStart = CMTimeSubtract(
            timestamp,
            CMTime(seconds: duration, preferredTimescale: CMTimeScale(Self.targetSampleRate))
        )
        let totalSamples = Int(duration * Self.targetSampleRate)
        let mic = extractAligned(from: microphone, windowStart: windowStart, windowEnd: timestamp, totalSamples: totalSamples)
        let sys = extractAligned(from: systemAudio, windowStart: windowStart, windowEnd: timestamp, totalSamples: totalSamples)
        return (mic, sys)
    }

    public func latestTimestamp() -> CMTime? { latestTime }

    // MARK: - Insert with overlap resolution

    private func insert(_ segment: AudioSegment, into segments: inout [AudioSegment]) {
        var i = 0
        var postClips: [AudioSegment] = []

        while i < segments.count {
            let existing = segments[i]

            if CMTimeCompare(segment.endTime, existing.startTime) <= 0 {
                break
            }

            if CMTimeCompare(segment.startTime, existing.endTime) >= 0 {
                i += 1
                continue
            }

            segments.remove(at: i)

            if CMTimeCompare(existing.startTime, segment.startTime) < 0 {
                let prefixCount = sampleCount(from: existing.startTime, to: segment.startTime, sr: existing.sampleRate)
                if prefixCount > 0 {
                    let prefix = Array(existing.samples.prefix(prefixCount))
                    segments.insert(
                        AudioSegment(samples: prefix, startTime: existing.startTime, source: existing.source, sampleRate: existing.sampleRate),
                        at: i)
                    i += 1
                }
            }

            if CMTimeCompare(existing.endTime, segment.endTime) > 0 {
                let prefixCount = sampleCount(from: existing.startTime, to: segment.endTime, sr: existing.sampleRate)
                if prefixCount < existing.samples.count {
                    let suffix = Array(existing.samples.suffix(from: prefixCount))
                    let suffixStart = CMTimeAdd(existing.startTime, CMTime(value: CMTimeValue(prefixCount), timescale: CMTimeScale(existing.sampleRate)))
                    postClips.append(
                        AudioSegment(samples: suffix, startTime: suffixStart, source: existing.source, sampleRate: existing.sampleRate)
                    )
                }
            }
        }

        segments.insert(segment, at: i)
        i += 1

        for clip in postClips {
            segments.insert(clip, at: i)
            i += 1
        }

        coalesce(&segments)
    }

    // MARK: - Coalesce adjacent compatible segments

    private func coalesce(_ segments: inout [AudioSegment]) {
        guard segments.count >= 2 else { return }
        var i = 0
        while i < segments.count - 1 {
            let cur = segments[i]
            let nxt = segments[i + 1]
            if cur.source == nxt.source,
               abs(cur.sampleRate - nxt.sampleRate) < 0.001,
               CMTimeCompare(cur.endTime, nxt.startTime) == 0 {
                let merged = AudioSegment(
                    samples: cur.samples + nxt.samples,
                    startTime: cur.startTime,
                    source: cur.source,
                    sampleRate: cur.sampleRate
                )
                segments[i] = merged
                segments.remove(at: i + 1)
            } else {
                i += 1
            }
        }
    }

    // MARK: - Helpers

    private func sampleCount(from start: CMTime, to end: CMTime, sr: Float64) -> Int {
        return max(0, Int(CMTimeGetSeconds(CMTimeSubtract(end, start)) * sr + 0.5))
    }

    private func evict(before latest: CMTime) {
        let cutoff = CMTimeSubtract(latest, CMTime(seconds: Self.retentionDuration, preferredTimescale: CMTimeScale(Self.targetSampleRate)))
        func prune(_ s: inout [AudioSegment]) {
            while let first = s.first, CMTimeCompare(first.endTime, cutoff) < 0 {
                s.removeFirst()
            }
        }
        prune(&microphone)
        prune(&systemAudio)
    }

    private func extractAligned(
        from segments: [AudioSegment],
        windowStart: CMTime,
        windowEnd: CMTime,
        totalSamples: Int
    ) -> [Float32] {
        var result = [Float32](repeating: 0, count: totalSamples)
        let winStartSec = CMTimeGetSeconds(windowStart)
        let winEndSec = CMTimeGetSeconds(windowEnd)

        for seg in segments {
            let segStartSec = CMTimeGetSeconds(seg.startTime)
            let segEndSec = CMTimeGetSeconds(seg.endTime)

            if segEndSec <= winStartSec { continue }
            if segStartSec >= winEndSec { continue }

            let overlapStart = max(segStartSec, winStartSec)
            let overlapEnd = min(segEndSec, winEndSec)
            guard overlapEnd > overlapStart + 1e-12 else { continue }

            let sampleOffset = Int((overlapStart - segStartSec) * seg.sampleRate + 0.5)
            let sampleEnd = Int((overlapEnd - segStartSec) * seg.sampleRate + 0.5)
            let copyCount = min(sampleEnd, seg.samples.count) - sampleOffset
            guard copyCount > 0 else { continue }

            let destOffset = Int((overlapStart - winStartSec) * Self.targetSampleRate + 0.5)
            guard destOffset < totalSamples else { continue }
            let copyDest = min(copyCount, totalSamples - destOffset)
            guard copyDest > 0 else { continue }

            result.replaceSubrange(
                destOffset..<destOffset + copyDest,
                with: seg.samples[sampleOffset..<sampleOffset + copyDest]
            )
        }

        return result
    }
}
