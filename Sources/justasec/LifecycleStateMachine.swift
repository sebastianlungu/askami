import Foundation
import os.lock

public enum LifecycleState: String, Sendable, Equatable {
    case startup
    case ready
    case processing
    case speaking
    case failed
}

public enum StateTransitionError: Error, Equatable {
    case invalidTransition(from: LifecycleState, to: LifecycleState)
}

public final class LifecycleStateMachine: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: LifecycleState.startup)

    public var state: LifecycleState {
        lock.withLock { $0 }
    }

    public var canTrigger: Bool { state == .ready }

    public init() {}

    public func startupComplete() throws {
        try lock.withLock { current in
            guard current == .startup || current == .failed else {
                throw StateTransitionError.invalidTransition(from: current, to: .ready)
            }
            current = .ready
        }
    }

    @discardableResult
    public func trigger() -> Bool {
        lock.withLock { current in
            guard current == .ready else { return false }
            current = .processing
            return true
        }
    }

    public func beginSpeaking() throws {
        try lock.withLock { current in
            guard current == .processing else {
                throw StateTransitionError.invalidTransition(from: current, to: .speaking)
            }
            current = .speaking
        }
    }

    public func speakingComplete() throws {
        try lock.withLock { current in
            guard current == .speaking else {
                throw StateTransitionError.invalidTransition(from: current, to: .ready)
            }
            current = .ready
        }
    }

    public func fail() {
        lock.withLock { $0 = .failed }
    }

    public func reset() throws {
        try lock.withLock { current in
            guard current == .failed else {
                throw StateTransitionError.invalidTransition(from: current, to: .ready)
            }
            current = .ready
        }
    }
}
