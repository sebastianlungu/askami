import Testing
@testable import askami

@Test("starts in startup state")
func initialState() {
    let machine = LifecycleStateMachine()
    #expect(machine.state == .startup)
}

@Test("canTrigger is false in startup")
func canTriggerStartup() {
    let machine = LifecycleStateMachine()
    #expect(!machine.canTrigger)
}

@Test("startup transitions to ready via startupComplete")
func startupToReady() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    #expect(machine.state == .ready)
}

@Test("canTrigger is true in ready state")
func canTriggerReady() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    #expect(machine.canTrigger)
}

@Test("ready accepts trigger and transitions to processing")
func readyAcceptsTrigger() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    let accepted = machine.trigger()
    #expect(accepted)
    #expect(machine.state == .processing)
}

@Test("canTrigger is false in processing")
func canTriggerProcessing() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    #expect(!machine.canTrigger)
}

@Test("trigger returns false when not in ready (startup)")
func triggerRejectedStartup() {
    let machine = LifecycleStateMachine()
    let accepted = machine.trigger()
    #expect(!accepted)
    #expect(machine.state == .startup)
}

@Test("trigger returns false when not in ready (processing)")
func triggerRejectedProcessing() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    let accepted = machine.trigger()
    #expect(!accepted)
    #expect(machine.state == .processing)
}

@Test("trigger returns false when not in ready (speaking)")
func triggerRejectedSpeaking() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    try machine.beginSpeaking()
    let accepted = machine.trigger()
    #expect(!accepted)
    #expect(machine.state == .speaking)
}

@Test("trigger returns false when not in ready (failed)")
func triggerRejectedFailed() throws {
    let machine = LifecycleStateMachine()
    machine.fail()
    let accepted = machine.trigger()
    #expect(!accepted)
    #expect(machine.state == .failed)
}

@Test("processing transitions to speaking via beginSpeaking")
func processingToSpeaking() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    try machine.beginSpeaking()
    #expect(machine.state == .speaking)
}

@Test("beginSpeaking from non-processing throws")
func beginSpeakingFromWrongState() {
    let machine = LifecycleStateMachine()
    #expect(throws: StateTransitionError.self) {
        try machine.beginSpeaking()
    }
}

@Test("speaking transitions to ready via speakingComplete")
func speakingToReady() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    try machine.beginSpeaking()
    try machine.speakingComplete()
    #expect(machine.state == .ready)
}

@Test("speakingComplete from non-speaking throws")
func speakingCompleteFromWrongState() {
    let machine = LifecycleStateMachine()
    #expect(throws: StateTransitionError.self) {
        try machine.speakingComplete()
    }
}

@Test("fail transitions from any state to failed")
func failFromAnyState() throws {
    var machine = LifecycleStateMachine()
    machine.fail()
    #expect(machine.state == .failed)

    machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.fail()
    #expect(machine.state == .failed)

    machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    machine.fail()
    #expect(machine.state == .failed)

    machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    try machine.beginSpeaking()
    machine.fail()
    #expect(machine.state == .failed)
}

@Test("failed transitions to ready via reset")
func failedToReady() throws {
    let machine = LifecycleStateMachine()
    machine.fail()
    try machine.reset()
    #expect(machine.state == .ready)
}

@Test("reset from non-failed throws")
func resetFromNonFailed() {
    let machine = LifecycleStateMachine()
    #expect(throws: StateTransitionError.self) {
        try machine.reset()
    }
}

@Test("startupComplete from processing throws")
func startupCompleteFromProcessing() throws {
    let machine = LifecycleStateMachine()
    try machine.startupComplete()
    machine.trigger()
    #expect(throws: StateTransitionError.self) {
        try machine.startupComplete()
    }
}

@Test("lifecycleState enum is Codable and Sendable")
func stateEnumConformances() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(LifecycleState.self)
    #expect(LifecycleState.startup.rawValue == "startup")
    #expect(LifecycleState.failed.rawValue == "failed")
}
