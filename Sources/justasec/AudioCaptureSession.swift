import Foundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreAudio

@MainActor
public protocol AudioCaptureSessionProtocol: AnyObject {
    func start() async throws
    func stop() async
}

@MainActor
public final class AudioCaptureSession: NSObject, AudioCaptureSessionProtocol {
    public typealias SampleHandler = @Sendable (AudioSamplePayload) -> Void
    public typealias ErrorHandler = @Sendable (AudioCaptureError) -> Void
    public typealias FormatChangeHandler = @Sendable (AudioStreamFormat, AudioSource) -> Void

    private let onSample: SampleHandler
    private let onError: ErrorHandler
    private let onFormatChange: FormatChangeHandler?

    private var stream: SCStream?
    private var stopping = false
    private let callbackQueue = DispatchQueue(
        label: "com.sebastianlungu.justasec.capture",
        qos: .userInitiated
    )
    private let formatTracker = FormatChangeTracker()

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
        guard stream == nil else { return }
        guard !stopping else {
            throw AudioCaptureError.streamFailed(
                "Cannot start while stopping"
            )
        }
        let filter = try await makeContentFilter()
        let config = makeConfiguration()
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = scStream
        try addAudioOutputs(to: scStream)
        do {
            try await scStream.startCapture()
        } catch {
            self.stream = nil
            throw AudioCaptureError.streamFailed(
                "Failed to start capture: \(error.localizedDescription)"
            )
        }
    }

    public func stop() async {
        guard let currentStream = stream else { return }
        stopping = true
        stream = nil
        await withCheckedContinuation { [onError] (continuation: CheckedContinuation<Void, Never>) in
            currentStream.stopCapture { error in
                if let error {
                    onError(.streamInterrupted(
                        "Stop failed: \(error.localizedDescription)"
                    ))
                }
                continuation.resume()
            }
        }
        stopping = false
    }

    private func makeContentFilter() async throws -> SCContentFilter {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw AudioCaptureError.permissionDenied(
                "Screen Recording permission denied: \(error.localizedDescription)"
            )
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.streamFailed(
                "No display available for audio capture"
            )
        }
        return SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.captureMicrophone = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1
        return config
    }

    private func addAudioOutputs(to stream: SCStream) throws {
        do {
            try stream.addStreamOutput(
                self, type: .audio, sampleHandlerQueue: callbackQueue
            )
            try stream.addStreamOutput(
                self, type: .microphone, sampleHandlerQueue: callbackQueue
            )
        } catch {
            throw AudioCaptureError.streamFailed(
                "Failed to add audio output: \(error.localizedDescription)"
            )
        }
    }
}

extension AudioCaptureSession: SCStreamDelegate {
    nonisolated public func stream(
        _ stream: SCStream, didStopWithError error: Error
    ) {
        onError(.streamInterrupted(
            "Stream stopped: \(error.localizedDescription)"
        ))
    }
}

extension AudioCaptureSession: SCStreamOutput {
    nonisolated public func stream(
        _ stream: SCStream,
        didOutput sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard let source = audioSource(for: type),
              let formatDesc = sampleBuffer.formatDescription,
              formatDesc.mediaType == .audio,
              let format = audioFormat(from: formatDesc),
              let data = extractAudioData(from: sampleBuffer)
        else { return }

        if formatTracker.updateIfChanged(format, source: source) {
            onFormatChange?(format, source)
        }

        onSample(AudioSamplePayload(
            data: data,
            timestamp: sampleBuffer.presentationTimeStamp,
            format: format,
            source: source
        ))
    }

    nonisolated private func audioSource(for type: SCStreamOutputType) -> AudioSource? {
        switch type {
        case .microphone: return .microphone
        case .audio: return .systemAudio
        default: return nil
        }
    }

    nonisolated private func audioFormat(
        from desc: CMAudioFormatDescription
    ) -> AudioStreamFormat? {
        guard let asbd = desc.audioStreamBasicDescription else { return nil }
        return AudioStreamFormat(
            sampleRate: asbd.mSampleRate,
            channelCount: asbd.mChannelsPerFrame,
            bytesPerFrame: asbd.mBytesPerFrame
        )
    }

    nonisolated private func extractAudioData(
        from sampleBuffer: CMSampleBuffer
    ) -> Data? {
        guard let blockBuffer = sampleBuffer.dataBuffer else { return nil }
        var pointer: UnsafeMutablePointer<Int8>?
        var length: Int = 0
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        )
        guard status == kCMBlockBufferNoErr, let pointer, length > 0
        else { return nil }
        return Data(bytes: pointer, count: length)
    }
}
