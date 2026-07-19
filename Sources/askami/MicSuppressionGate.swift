import Foundation
import os.lock

private enum SuppressionState: Sendable {
    case idle
    case suppressing
    case settle(until: TimeInterval)
}

public final class MicSuppressionGate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: SuppressionState.idle)

    public init() {}

    public var isSuppressing: Bool {
        state.withLock {
            switch $0 {
            case .idle: return false
            case .suppressing, .settle: return true
            }
        }
    }

    public func startSuppression() {
        state.withLock { $0 = .suppressing }
    }

    public func endSuppression(after settleDuration: TimeInterval = 0.5) async {
        let until = ProcessInfo.processInfo.systemUptime + settleDuration
        state.withLock { $0 = .settle(until: until) }
        try? await Task.sleep(nanoseconds: UInt64(settleDuration * 1_000_000_000))
        state.withLock {
            if case .settle(let u) = $0, ProcessInfo.processInfo.systemUptime >= u {
                $0 = .idle
            }
        }
    }

    public func shouldDiscard(source: AudioSource) -> Bool {
        state.withLock {
            switch $0 {
            case .idle: return false
            case .suppressing, .settle:
                return source == .microphone
            }
        }
    }
}
