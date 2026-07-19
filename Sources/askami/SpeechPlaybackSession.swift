@preconcurrency import AVFoundation
import KokoroCoreML
import os.lock

actor PlaybackSession {
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let _cancelled = OSAllocatedUnfairLock(initialState: false)
    private let _pendingCount = OSAllocatedUnfairLock(initialState: 0)
    private let _drainContinuation = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
    private static let maxBuffered = 4
    private static let backpressureTimeout: Duration = .seconds(5)

    init?() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: KokoroEngine.audioFormat)
        do {
            try engine.start()
        } catch {
            fputs("askami: audio engine unavailable - \(error)\n", stderr)
            return nil
        }
        player.play()
        self.engine = engine
        self.player = player
    }

    /// Schedule a buffer for playback. Returns false on cancellation or timeout.
    /// The package's paceToRealtime paces the producer; this is a local safety cap.
    func enqueue(_ buffer: AVAudioPCMBuffer) async -> Bool {
        if _cancelled.withLock({ $0 }) { return false }
        let deadline = ContinuousClock.now + Self.backpressureTimeout
        while _pendingCount.withLock({ $0 }) >= Self.maxBuffered {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if _cancelled.withLock({ $0 }) { return false }
            if ContinuousClock.now >= deadline { return false }
        }
        _pendingCount.withLock { $0 += 1 }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: { [count = _pendingCount] (_: AVAudioPlayerNodeCompletionCallbackType) in
            count.withLock { $0 -= 1 }
        })
        return true
    }

    /// Wait for all enqueued audio to finish playing. Uses a stored continuation
    /// so cancel() can also resume it, preventing leaks.
    func drain() async {
        if _cancelled.withLock({ $0 }) { return }
        if _drainContinuation.withLock({ $0 }) != nil { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            _drainContinuation.withLock { $0 = cont }
            let fmt = KokoroEngine.audioFormat
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) else {
                resumeDrain()
                return
            }
            buf.frameLength = 1
            buf.floatChannelData?[0][0] = 0
            player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack, completionHandler: { [weak self] (_: AVAudioPlayerNodeCompletionCallbackType) in
                self?.resumeDrain()
            })
        }
    }

    private nonisolated func resumeDrain() {
        let cont = _drainContinuation.withLock { continuation -> CheckedContinuation<Void, Never>? in
            let saved = continuation
            continuation = nil
            return saved
        }
        cont?.resume()
    }

    func cancel() {
        _cancelled.withLock { $0 = true }
        engine.stop()
        resumeDrain()
    }

    var isCancelled: Bool { _cancelled.withLock { $0 } }
}
