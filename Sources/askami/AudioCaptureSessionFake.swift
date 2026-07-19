import Foundation
import CoreMedia

@MainActor
public final class AudioCaptureSessionFake: AudioCaptureSessionProtocol {
    public typealias SampleHandler = @Sendable (AudioSamplePayload) -> Void
    public typealias ErrorHandler = @Sendable (AudioCaptureError) -> Void
    public typealias FormatChangeHandler = @Sendable (AudioStreamFormat, AudioSource) -> Void

    public private(set) var isRunning = false
    public private(set) var isStopping = false
    public private(set) var stopError: AudioCaptureError?

    private let onSample: SampleHandler
    private let onError: ErrorHandler
    private let onFormatChange: FormatChangeHandler?

    public init(
        onSample: @escaping SampleHandler,
        onError: @escaping ErrorHandler,
        onFormatChange: FormatChangeHandler? = nil
    ) {
        self.onSample = onSample
        self.onError = onError
        self.onFormatChange = onFormatChange
    }

    public func start() async throws {
        guard !isStopping else {
            throw AudioCaptureError.streamFailed(
                "Cannot start while stopping"
            )
        }
        isRunning = true
    }

    public func stop() async {
        guard isRunning else { return }
        isStopping = true
        isRunning = false
        if let error = stopError {
            onError(error)
            self.stopError = nil
        }
        isStopping = false
    }

    public func injectSample(_ payload: AudioSamplePayload) {
        onSample(payload)
    }

    public func injectError(_ error: AudioCaptureError) {
        onError(error)
    }

    public func injectFormatChange(format: AudioStreamFormat, source: AudioSource) {
        onFormatChange?(format, source)
    }

    public func injectStopError(_ error: AudioCaptureError) {
        stopError = error
    }
}
