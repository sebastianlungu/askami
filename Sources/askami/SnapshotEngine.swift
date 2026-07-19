import Foundation
import CoreMedia

public final class SnapshotEngine: Sendable {
    // Invariant: all mutable state resides inside the `timeline` actor, which
    // serializes all access. The class holds let references to the actor and
    // a Sendable closure; Swift 6 accepts `final class: Sendable` when every
    // stored property is immutable and Sendable.

    private let timeline = AudioTimeline()
    private let onError: (@Sendable (AudioPipelineError) -> Void)?

    public init(onError: (@Sendable (AudioPipelineError) -> Void)? = nil) {
        self.onError = onError
    }

    public func ingestPayload(_ payload: AudioSamplePayload) async {
        do {
            let segment = try AudioConverter.convert(payload)
            await timeline.ingest(segment)
        } catch let error as AudioPipelineError {
            onError?(error)
        } catch {
            onError?(.conversionFailed("unexpected: \(error.localizedDescription)"))
        }
    }

    public func snapshot(before timestamp: CMTime, duration: TimeInterval = 30.0) async throws -> Data? {
        let snap = await timeline.snapshot(before: timestamp, duration: duration)
        let mixed = AudioMixer.mix(microphone: snap.microphone, systemAudio: snap.systemAudio)
        guard !EnergyGate.isSilent(mixed) else { return nil }
        return try WAVEncoder.encodePCM16(mixed, sampleRate: 16000)
    }

    public func currentCaptureTime() async -> CMTime? {
        await timeline.latestTimestamp()
    }
}
