import AppKit
import Foundation

public enum DockStatus: String, Sendable, Equatable, CaseIterable {
    case launching
    case listening
    case stt
    case agent
    case success
    case tts
    case error
}

@MainActor
public final class DockStatusPresenter {

    // MARK: - Configuration

    internal static let pulseIntervalNanoseconds: UInt64 = 500_000_000

    private static let iconDimension: CGFloat = 512
    private static let cornerRadius: CGFloat = 110
    private static let symbolPointSize: CGFloat = 200
    private static let baseBackground = NSColor(white: 0.13, alpha: 1.0)
    private static let accentLineWidth: CGFloat = 4
    private static let accentInset: CGFloat = 8

    private static let symbolNames: [DockStatus: String] = [
        .launching: "hourglass",
        .listening: "mic.fill",
        .stt: "waveform",
        .agent: "sparkle",
        .success: "checkmark.circle.fill",
        .tts: "speaker.wave.2.fill",
        .error: "exclamationmark.triangle.fill",
    ]

    private static let colors: [DockStatus: NSColor] = [
        .launching: .systemGray,
        .listening: .systemBlue,
        .stt: .systemPurple,
        .agent: .systemOrange,
        .success: .systemGreen,
        .tts: NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1.0),
        .error: .systemRed,
    ]

    // MARK: - Public State

    public private(set) var currentStatus: DockStatus
    public private(set) var isPulsing = false

    // MARK: - Injectable Seams (for testing)

    internal var readReduceMotion: @Sendable () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    internal var pulseSleeper: @Sendable () async -> Void = {
        try? await Task.sleep(nanoseconds: DockStatusPresenter.pulseIntervalNanoseconds)
    }

    internal var onReduceMotionEvent: @Sendable () -> Void = {}

    internal let reduceMotionNotificationCenter: NotificationCenter

    // MARK: - Private State

    internal private(set) var pulseTask: Task<Void, Never>?
    internal private(set) var reduceMotionTask: Task<Void, Never>?
    internal let fullImageCache: [DockStatus: NSImage]
    internal let subtleListeningImage: NSImage

    // MARK: - Initialization

    public init(
        initialStatus: DockStatus = .launching,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.currentStatus = initialStatus
        self.reduceMotionNotificationCenter = notificationCenter
        self.fullImageCache = Self.generateAllImages()
        self.subtleListeningImage = Self.generateListeningSubtle()

        reduceMotionTask = Task { @MainActor [weak self] in
            for await _ in notificationCenter.notifications(
                named: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            ) {
                guard let self else { return }
                handleReduceMotionChanged()
            }
        }

        applyCurrentStatus()
    }

    deinit {
        reduceMotionTask?.cancel()
        pulseTask?.cancel()
    }

    // MARK: - Public API

    public func transition(to status: DockStatus) {
        stopPulse()
        currentStatus = status
        applyCurrentStatus()
    }

    public func cleanup() {
        stopPulse()
        reduceMotionTask?.cancel()
        reduceMotionTask = nil
    }

    // MARK: - Image Generation

    private static func generateAllImages() -> [DockStatus: NSImage] {
        var cache: [DockStatus: NSImage] = [:]
        for status in DockStatus.allCases {
            guard let image = render(status: status) else { continue }
            cache[status] = image
        }
        return cache
    }

    private static func generateListeningSubtle() -> NSImage {
        guard let image = render(status: .listening, symbolAlpha: 0.6) else {
            return NSImage(size: NSSize(width: iconDimension, height: iconDimension))
        }
        return image
    }

    private static func drawBaseAndAccent(in ctx: CGContext, rect: CGRect, color: CGColor) {
        let basePath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setFillColor(baseBackground.cgColor)
        ctx.addPath(basePath)
        ctx.fillPath()

        let insetRect = rect.insetBy(dx: accentInset, dy: accentInset)
        let accentPath = CGPath(
            roundedRect: insetRect,
            cornerWidth: cornerRadius - accentInset,
            cornerHeight: cornerRadius - accentInset,
            transform: nil
        )
        ctx.setStrokeColor(color)
        ctx.setLineWidth(accentLineWidth)
        ctx.addPath(accentPath)
        ctx.strokePath()
    }

    private static func drawSymbol(in ctx: CGContext, rect: CGRect, name: String, color: CGColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let symSize = configured.size
        let symRect = CGRect(
            x: (rect.width - symSize.width) / 2,
            y: (rect.height - symSize.height) / 2,
            width: symSize.width,
            height: symSize.height
        )
        guard let cgSymbol = configured.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        ctx.saveGState()
        ctx.setAlpha(color.alpha)
        ctx.clip(to: symRect, mask: cgSymbol)
        ctx.setFillColor(color)
        ctx.fill(symRect)
        ctx.restoreGState()
    }

    private static func render(status: DockStatus, symbolAlpha: CGFloat = 1.0) -> NSImage? {
        guard let color = colors[status] else { return nil }
        guard let symbolName = symbolNames[status] else { return nil }

        let size = NSSize(width: iconDimension, height: iconDimension)
        let image = NSImage(size: size)

        image.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        let rect = CGRect(origin: .zero, size: size)

        let drawColor = color.withAlphaComponent(symbolAlpha)
        drawBaseAndAccent(in: ctx, rect: rect, color: drawColor.cgColor)
        drawSymbol(in: ctx, rect: rect, name: symbolName, color: drawColor.cgColor)

        image.unlockFocus()
        return image
    }

    // MARK: - Pulse

    private func startPulse() {
        guard !readReduceMotion() else { return }
        stopPulse()
        isPulsing = true
        pulseTask = Task { @MainActor [weak self] in
            var showFull = true
            while !Task.isCancelled {
                await self?.pulseSleeper()
                guard let self, !Task.isCancelled else { return }
                if showFull {
                    if let image = fullImageCache[.listening] {
                        NSApplication.shared.applicationIconImage = image
                    }
                } else {
                    NSApplication.shared.applicationIconImage = subtleListeningImage
                }
                showFull.toggle()
            }
        }
    }

    private func stopPulse() {
        isPulsing = false
        pulseTask?.cancel()
        pulseTask = nil
    }

    // MARK: - Apply

    private func applyCurrentStatus() {
        guard let image = fullImageCache[currentStatus] else { return }
        NSApplication.shared.applicationIconImage = image
        if currentStatus == .listening {
            startPulse()
        }
    }

    // MARK: - Reduce Motion

    internal func handleReduceMotionChanged() {
        onReduceMotionEvent()
        if readReduceMotion() {
            stopPulse()
            if currentStatus == .listening, let image = fullImageCache[.listening] {
                NSApplication.shared.applicationIconImage = image
            }
        } else if currentStatus == .listening {
            startPulse()
        }
    }
}
