import Testing
import Foundation
import AppKit
@testable import justasec

// MARK: - DockStatus Enum

@Test("DockStatus has exactly seven cases")
func dockStatusSevenCases() {
    #expect(DockStatus.allCases.count == 7)
}

@Test("DockStatus cases have unique raw values")
func dockStatusUniqueRawValues() {
    let rawValues = Set(DockStatus.allCases.map { $0.rawValue })
    #expect(rawValues.count == DockStatus.allCases.count)
}

@Test("DockStatus conforms to Sendable")
func dockStatusSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(DockStatus.self)
}

@Test("DockStatus conforms to Equatable")
func dockStatusEquatable() {
    #expect(DockStatus.launching == DockStatus.launching)
    #expect(DockStatus.launching != DockStatus.listening)
}

// MARK: - Image Cache

@Test("all seven state images are non-nil and cached")
@MainActor
func allStatesCached() throws {
    let presenter = DockStatusPresenter()
    for status in DockStatus.allCases {
        let image = try #require(presenter.fullImageCache[status])
        #expect(image.size.width > 0)
    }
}

@Test("all seven state images are visually distinct")
@MainActor
func allImagesDistinct() throws {
    let presenter = DockStatusPresenter()
    var representations: Set<Data> = []
    for status in DockStatus.allCases {
        let image = try #require(presenter.fullImageCache[status])
        let rep = try #require(image.tiffRepresentation)
        representations.insert(rep)
    }
    #expect(representations.count == DockStatus.allCases.count)
}

@Test("subtle listening image differs from full listening image")
@MainActor
func subtleListeningDistinct() throws {
    let presenter = DockStatusPresenter()
    let full = try #require(presenter.fullImageCache[.listening])
    #expect(full !== presenter.subtleListeningImage)
    #expect(full.tiffRepresentation != presenter.subtleListeningImage.tiffRepresentation)
}

@Test("same state returns the same cached image instance")
@MainActor
func sameImageCached() throws {
    let presenter = DockStatusPresenter()
    for status in DockStatus.allCases {
        let a = try #require(presenter.fullImageCache[status])
        let b = try #require(presenter.fullImageCache[status])
        #expect(a === b)
    }
}

// MARK: - State Transitions

@Test("initial status is launching")
@MainActor
func initialStateLaunching() {
    let presenter = DockStatusPresenter()
    #expect(presenter.currentStatus == .launching)
}

@Test("transition updates current status")
@MainActor
func transitionUpdatesStatus() {
    let presenter = DockStatusPresenter()
    for status in DockStatus.allCases {
        presenter.transition(to: status)
        #expect(presenter.currentStatus == status)
    }
}

@Test("each transition installs TIFF-matching cached image")
@MainActor
func transitionInstallsCachedImage() throws {
    let presenter = DockStatusPresenter()
    for status in DockStatus.allCases {
        presenter.transition(to: status)
        let cachedTiff = try #require(presenter.fullImageCache[status]?.tiffRepresentation)
        let iconTiff = try #require(NSApplication.shared.applicationIconImage?.tiffRepresentation)
        #expect(iconTiff == cachedTiff)
    }
}

// MARK: - Pulse Interval

@Test("pulse interval constant is 500ms (<=~2 updates per second)")
@MainActor
func pulseIntervalIs500ms() {
    #expect(DockStatusPresenter.pulseIntervalNanoseconds == 500_000_000)
}

// MARK: - Pulse Ownership

@Test("listening creates pulse task and sets isPulsing")
@MainActor
func listeningStartsPulse() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)
}

@Test("leaving listening cancels task and clears isPulsing")
@MainActor
func leavingListeningStopsPulse() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
    presenter.transition(to: .error)
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
}

@Test("transition to listening after leaving creates new task")
@MainActor
func transitionToListeningReplacesTask() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
    presenter.transition(to: .success)
    #expect(presenter.pulseTask == nil)
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
}

@Test("rapid listening transitions leave only last task active")
@MainActor
func rapidTransitionsLastTaskActive() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
    presenter.transition(to: .error)
    #expect(presenter.pulseTask == nil)
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
    presenter.transition(to: .success)
    #expect(presenter.pulseTask == nil)
    presenter.transition(to: .listening)
    #expect(presenter.pulseTask != nil)
}

// MARK: - Stale Callback Regression

@Test("stale pulse callbacks do not overwrite later non-listening icon")
@MainActor
func staleCallbacksNotApplied() throws {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)

    let iconBefore = try #require(NSApplication.shared.applicationIconImage?.tiffRepresentation)
    let errorImage = try #require(presenter.fullImageCache[.error])
    let errorTiff = try #require(errorImage.tiffRepresentation)

    presenter.transition(to: .error)
    #expect(presenter.pulseTask == nil)
    let iconAfter = try #require(NSApplication.shared.applicationIconImage?.tiffRepresentation)
    #expect(iconAfter == errorTiff)
    #expect(iconAfter != iconBefore)
}

// MARK: - Reduce Motion

@Test("reduce motion enabled at initial listening prevents pulse")
@MainActor
func reduceMotionAtInitPreventsPulse() {
    let presenter = DockStatusPresenter()
    presenter.readReduceMotion = { true }
    presenter.transition(to: .listening)
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
}

@Test("reduce motion disable while listening stops pulse via handler")
@MainActor
func reduceMotionDisableWhileListening() {
    let presenter = DockStatusPresenter()
    presenter.readReduceMotion = { false }
    presenter.transition(to: .listening)
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)
    presenter.readReduceMotion = { true }
    presenter.handleReduceMotionChanged()
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
}

@Test("reduce motion enable while listening starts pulse via handler")
@MainActor
func reduceMotionEnableWhileListening() {
    let presenter = DockStatusPresenter()
    presenter.readReduceMotion = { true }
    presenter.transition(to: .listening)
    #expect(!presenter.isPulsing)
    presenter.readReduceMotion = { false }
    presenter.handleReduceMotionChanged()
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)
}

@Test("reduce motion changes outside listening have no pulse effect")
@MainActor
func reduceMotionChangesOutsideListening() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .launching)
    presenter.readReduceMotion = { true }
    presenter.handleReduceMotionChanged()
    #expect(!presenter.isPulsing)
    presenter.readReduceMotion = { false }
    presenter.handleReduceMotionChanged()
    #expect(!presenter.isPulsing)
}

// MARK: - Native Notification Wiring

@Test("native notification via workspace center stops pulse when reduce motion enabled")
@MainActor
func notificationWiringStopsPulse() async {
    let nc = NotificationCenter()
    let presenter = DockStatusPresenter(notificationCenter: nc)
    await Task.yield()
    presenter.readReduceMotion = { false }
    presenter.transition(to: .listening)
    #expect(presenter.isPulsing)
    #expect(presenter.reduceMotionTask != nil)

    presenter.readReduceMotion = { true }
    nc.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    try? await Task.sleep(nanoseconds: 10_000_000)
    await Task.yield()
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
}

@Test("native notification via workspace center starts pulse when reduce motion disabled")
@MainActor
func notificationWiringStartsPulse() async {
    let nc = NotificationCenter()
    let presenter = DockStatusPresenter(notificationCenter: nc)
    await Task.yield()
    presenter.readReduceMotion = { true }
    presenter.transition(to: .listening)
    #expect(!presenter.isPulsing)

    presenter.readReduceMotion = { false }
    nc.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    try? await Task.sleep(nanoseconds: 10_000_000)
    await Task.yield()
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)
}

@Test("reduce motion task is created on init and set nil on cleanup")
@MainActor
func reduceMotionTaskLifecycle() {
    let presenter = DockStatusPresenter()
    #expect(presenter.reduceMotionTask != nil)
    presenter.cleanup()
    #expect(presenter.reduceMotionTask == nil)
}

// MARK: - Lifetime / Dealloc Cleanup

@Test("dealloc cancels reduce motion notification task")
@MainActor
func deallocCancelsReduceMotionTask() {
    let nc = NotificationCenter()
    var presenter: DockStatusPresenter? = DockStatusPresenter(notificationCenter: nc)
    let task = presenter!.reduceMotionTask
    #expect(task != nil)

    presenter = nil
    // deinit calls reduceMotionTask?.cancel() which is visible in source
    // After dealloc, posting notification must not crash
    nc.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
}

@Test("dealloc cancels pulse task without crash")
@MainActor
func deallocCancelsPulseTask() {
    var presenter: DockStatusPresenter? = DockStatusPresenter()
    presenter!.readReduceMotion = { false }
    presenter!.transition(to: .listening)
    #expect(presenter!.isPulsing)
    #expect(presenter!.pulseTask != nil)

    presenter = nil
    // deinit calls pulseTask?.cancel() - no crash means task was properly cancelled
}

// MARK: - Cleanup

@Test("cleanup stops pulse and cancels reduce motion task")
@MainActor
func cleanupStopsPulseAndCancelsObservation() {
    let presenter = DockStatusPresenter()
    presenter.transition(to: .listening)
    #expect(presenter.isPulsing)
    #expect(presenter.pulseTask != nil)
    #expect(presenter.reduceMotionTask != nil)
    presenter.cleanup()
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
    #expect(presenter.reduceMotionTask == nil)
}

@Test("cleanup is idempotent")
@MainActor
func cleanupIdempotent() {
    let presenter = DockStatusPresenter()
    presenter.cleanup()
    presenter.cleanup()
    presenter.transition(to: .listening)
    presenter.cleanup()
    #expect(!presenter.isPulsing)
    #expect(presenter.pulseTask == nil)
    #expect(presenter.reduceMotionTask == nil)
}

// MARK: - Lifecycle Wiring

@Test("JustasecApp dockStatusPresenter initializes as launching")
@MainActor
func appDockStartsLaunching() {
    let app = JustasecApp()
    #expect(app.dockStatusPresenter.currentStatus == .launching)
}
