import CoreMedia
import CoreAudio
import os.lock

public enum AudioSource: String, Sendable, Equatable, Codable {
    case microphone
    case systemAudio
}

public struct AudioStreamFormat: Sendable, Equatable {
    public let sampleRate: Float64
    public let channelCount: UInt32
    public let bytesPerFrame: UInt32

    public init(sampleRate: Float64, channelCount: UInt32, bytesPerFrame: UInt32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bytesPerFrame = bytesPerFrame
    }

    public var durationForByteCount: (_ byteCount: Int) -> TimeInterval {
        return { byteCount in
            let bytesPerSecond = self.sampleRate * Double(self.channelCount) * Double(self.bytesPerFrame)
            guard bytesPerSecond > 0 else { return 0 }
            return Double(byteCount) / bytesPerSecond
        }
    }
}

public struct AudioSamplePayload: Sendable {
    public let data: Data
    public let timestamp: CMTime
    public let format: AudioStreamFormat
    public let source: AudioSource

    public init(data: Data, timestamp: CMTime, format: AudioStreamFormat, source: AudioSource) {
        self.data = data
        self.timestamp = timestamp
        self.format = format
        self.source = source
    }
}

public enum AudioCaptureError: Error, Sendable, Equatable {
    case permissionDenied(String)
    case streamFailed(String)
    case unsupported
    case streamInterrupted(String)
}

private struct FormatState: Sendable {
    var microphone: AudioStreamFormat?
    var systemAudio: AudioStreamFormat?
}

/// Tracks per-source audio format state from nonisolated capture callbacks.
/// Thread-safe via OSAllocatedUnfairLock; no @unchecked Sendable needed.
public final class FormatChangeTracker: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: FormatState())

    public init() {}

    /// Returns true when the format differs from a previously registered value
    /// for the same source. Returns false on first registration (initial format)
    /// or when the format is unchanged.
    public func updateIfChanged(
        _ format: AudioStreamFormat,
        source: AudioSource
    ) -> Bool {
        lock.withLock { state in
            let current: AudioStreamFormat?
            switch source {
            case .microphone: current = state.microphone
            case .systemAudio: current = state.systemAudio
            }
            guard current != format else { return false }
            switch source {
            case .microphone: state.microphone = format
            case .systemAudio: state.systemAudio = format
            }
            return current != nil
        }
    }
}
