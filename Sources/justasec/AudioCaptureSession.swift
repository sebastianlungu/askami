import Foundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import AVFoundation
import CoreMedia
import CoreAudio
import os.lock

private final class CaptureDiagnostics: Sendable {
    private let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    func logOnce(_ key: String, _ message: String) {
        let isNew = reported.withLock { $0.insert(key).inserted }
        if isNew { fputs("justasec: capture diagnostic: \(message)\n", stderr) }
    }
}

private final class CaptureOutputHandler: NSObject, SCStreamOutput {
    private let onSample: AudioCaptureSession.SampleHandler
    private let onFormatChange: AudioCaptureSession.FormatChangeHandler?
    private let formatTracker = FormatChangeTracker()
    private let diagnostics = CaptureDiagnostics()

    init(
        onSample: @escaping AudioCaptureSession.SampleHandler,
        onFormatChange: AudioCaptureSession.FormatChangeHandler?
    ) {
        self.onSample = onSample
        self.onFormatChange = onFormatChange
    }

    func stream(
        _ stream: SCStream,
        didOutput sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        diagnostics.logOnce("raw-\(type.rawValue)", "received output type \(type.rawValue)")
        guard let source = audioSource(for: type) else { return }
        diagnostics.logOnce("callback-\(source.rawValue)", "received \(source.rawValue) callback")
        guard let formatDesc = sampleBuffer.formatDescription else {
            diagnostics.logOnce("format-missing-\(source.rawValue)", "\(source.rawValue) format missing")
            return
        }
        guard formatDesc.mediaType == .audio else {
            diagnostics.logOnce("media-\(source.rawValue)", "\(source.rawValue) media type is not audio")
            return
        }
        guard let format = audioFormat(from: formatDesc) else {
            diagnostics.logOnce("format-unsupported-\(source.rawValue)", "\(source.rawValue) format unsupported")
            return
        }
        guard let data = Self.extractAudioData(from: sampleBuffer) else {
            diagnostics.logOnce("data-\(source.rawValue)", "\(source.rawValue) data extraction failed")
            return
        }

        if formatTracker.updateIfChanged(format, source: source) {
            onFormatChange?(format, source)
        }
        onSample(AudioSamplePayload(
            data: data,
            timestamp: sampleBuffer.presentationTimeStamp,
            format: format,
            source: source
        ))
        diagnostics.logOnce(
            "delivered-\(source.rawValue)",
            "delivered \(source.rawValue) samples (\(data.count) bytes)"
        )
    }

    private func audioSource(for type: SCStreamOutputType) -> AudioSource? {
        switch type {
        case .microphone: return .microphone
        case .audio: return .systemAudio
        default: return nil
        }
    }

    private func audioFormat(
        from desc: CMAudioFormatDescription
    ) -> AudioStreamFormat? {
        guard let asbd = desc.audioStreamBasicDescription else { return nil }
        let isFloat = asbd.mFormatFlags & UInt32(kAudioFormatFlagIsFloat) != 0
        let pcm: PCMFormat
        if isFloat && asbd.mBitsPerChannel == 32 { pcm = .float32 }
        else if !isFloat && asbd.mBitsPerChannel == 16 { pcm = .int16 }
        else { pcm = .unknown }
        return AudioStreamFormat(
            sampleRate: asbd.mSampleRate,
            channelCount: asbd.mChannelsPerFrame,
            bytesPerFrame: asbd.mBytesPerFrame,
            pcmFormat: pcm
        )
    }

    static func extractAudioData(from sampleBuffer: CMSampleBuffer) -> Data? {
        let flags = UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment)
        var requiredSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: flags,
            blockBufferOut: nil
        ) == noErr, requiredSize > 0 else { return nil }

        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: 16
        )
        defer { rawList.deallocate() }
        let audioList = rawList.assumingMemoryBound(to: AudioBufferList.self)
        var retainedBlock: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: flags,
            blockBufferOut: &retainedBlock
        ) == noErr else { return nil }

        var data = Data()
        for buffer in UnsafeMutableAudioBufferListPointer(audioList) {
            guard let bytes = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            data.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(buffer.mDataByteSize))
        }
        return data.isEmpty ? nil : data
    }
}

@MainActor
private final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private let onSample: AudioCaptureSession.SampleHandler
    private var isRunning = false

    init(onSample: @escaping AudioCaptureSession.SampleHandler) {
        self.onSample = onSample
    }

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.streamFailed("No microphone input format")
        }
        let tap = Self.makeTapHandler(onSample: onSample)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.streamFailed(
                "Failed to start microphone: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    nonisolated private static func makeTapHandler(
        onSample: @escaping AudioCaptureSession.SampleHandler
    ) -> AVAudioNodeTapBlock {
        { buffer, time in
            guard let payload = makePayload(buffer: buffer, time: time) else { return }
            onSample(payload)
        }
    }

    nonisolated private static func makePayload(
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime
    ) -> AudioSamplePayload? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return nil }

        var mono = [Float32](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                mono[frame] += channels[channel][frame] / Float32(channelCount)
            }
        }
        let seconds = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : ProcessInfo.processInfo.systemUptime
        return AudioSamplePayload(
            data: mono.withUnsafeBytes { Data($0) },
            timestamp: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
            format: AudioStreamFormat(
                sampleRate: buffer.format.sampleRate,
                channelCount: 1,
                bytesPerFrame: UInt32(MemoryLayout<Float32>.stride),
                pcmFormat: .float32
            ),
            source: .microphone
        )
    }
}

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

    private let onError: ErrorHandler
    private let outputHandler: CaptureOutputHandler
    private let microphoneCapture: MicrophoneCapture

    private var stream: SCStream?
    private var stopping = false
    private let screenQueue = DispatchQueue(
        label: "com.sebastianlungu.justasec.capture.screen",
        qos: .utility
    )
    private let systemAudioQueue = DispatchQueue(
        label: "com.sebastianlungu.justasec.capture.system-audio",
        qos: .userInitiated
    )
    public init(
        onSample: @escaping SampleHandler,
        onError: @escaping ErrorHandler,
        onFormatChange: FormatChangeHandler? = nil
    ) {
        self.onError = onError
        self.outputHandler = CaptureOutputHandler(
            onSample: onSample,
            onFormatChange: onFormatChange
        )
        self.microphoneCapture = MicrophoneCapture(onSample: onSample)
        super.init()
    }

    public func start() async throws {
        guard stream == nil else { return }
        guard !stopping else {
            throw AudioCaptureError.streamFailed(
                "Cannot start while stopping"
            )
        }
        let filter = try await makeContentFilter()
        let config = Self.makeConfiguration()
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = scStream
        try addStreamOutputs(to: scStream)
        do {
            try microphoneCapture.start()
            try await scStream.startCapture()
        } catch {
            microphoneCapture.stop()
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
        microphoneCapture.stop()
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

    static func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        config.queueDepth = 1
        config.capturesAudio = true
        config.captureMicrophone = false
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1
        return config
    }

    private func addStreamOutputs(to stream: SCStream) throws {
        do {
            try stream.addStreamOutput(
                outputHandler, type: .screen, sampleHandlerQueue: screenQueue
            )
            try stream.addStreamOutput(
                outputHandler, type: .audio, sampleHandlerQueue: systemAudioQueue
            )
        } catch {
            throw AudioCaptureError.streamFailed(
                "Failed to add audio output: \(error.localizedDescription)"
            )
        }
    }

    nonisolated static func extractAudioData(
        from sampleBuffer: CMSampleBuffer
    ) -> Data? {
        CaptureOutputHandler.extractAudioData(from: sampleBuffer)
    }
}

extension AudioCaptureSession: SCStreamDelegate {
    nonisolated public func stream(
        _ stream: SCStream, didStopWithError error: Error
    ) {
        let capturedError = error
        Task { @MainActor in
            onError(.streamInterrupted("Stream stopped: \(capturedError.localizedDescription)"))
        }
    }
}
