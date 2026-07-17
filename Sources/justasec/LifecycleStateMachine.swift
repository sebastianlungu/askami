import Foundation

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

public struct LifecycleStateMachine: Sendable {
    public private(set) var state: LifecycleState = .startup

    public var canTrigger: Bool { state == .ready }

    public init() {}

    public mutating func startupComplete() throws {
        try transition(from: [.startup, .failed], to: .ready)
    }

    @discardableResult
    public mutating func trigger() -> Bool {
        guard state == .ready else { return false }
        state = .processing
        return true
    }

    public mutating func beginSpeaking() throws {
        try transition(from: [.processing], to: .speaking)
    }

    public mutating func speakingComplete() throws {
        try transition(from: [.speaking], to: .ready)
    }

    public mutating func fail() {
        state = .failed
    }

    public mutating func reset() throws {
        try transition(from: [.failed], to: .ready)
    }

    private mutating func transition(from allowed: Set<LifecycleState>, to newState: LifecycleState) throws {
        guard allowed.contains(state) else {
            throw StateTransitionError.invalidTransition(from: state, to: newState)
        }
        state = newState
    }
}
