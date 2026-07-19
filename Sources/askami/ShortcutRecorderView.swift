import AppKit
import Carbon

@MainActor
public protocol ShortcutRecorderDelegate: AnyObject {
    func shortcutRecorderDidRecord(_ shortcut: ShortcutValue)
    func shortcutRecorderDidCancel()
    func shortcutRecorderDidReject()
}

@MainActor
public final class ShortcutRecorderView: NSView {
    public private(set) var shortcut: ShortcutValue
    public weak var delegate: ShortcutRecorderDelegate?

    private let displayField: NSTextField
    private var isRecording = false

    public init(shortcut: ShortcutValue) {
        self.shortcut = shortcut
        self.displayField = NSTextField(labelWithString: shortcut.displayString)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateShortcut(_ newShortcut: ShortcutValue) {
        shortcut = newShortcut
        isRecording = false
        updateDisplay()
    }

    private func setupView() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 4
        setAccessibilityRole(.button)
        setAccessibilityLabel("Global shortcut recorder. Click to record a new shortcut.")

        displayField.translatesAutoresizingMaskIntoConstraints = false
        displayField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        displayField.alignment = .center
        displayField.setAccessibilityLabel("Current shortcut value")

        addSubview(displayField)
        NSLayoutConstraint.activate([
            displayField.centerXAnchor.constraint(equalTo: centerXAnchor),
            displayField.centerYAnchor.constraint(equalTo: centerYAnchor),
            displayField.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            displayField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    public override func becomeFirstResponder() -> Bool {
        isRecording = true
        updateDisplay()
        setRecordingAppearance(true)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        isRecording = false
        updateDisplay()
        setRecordingAppearance(false)
        return true
    }

    public override func keyDown(with event: NSEvent) {
        handleKeyEvent(event)
    }

    public func handleKeyEvent(_ event: NSEvent) {
        let result = ShortcutInputValidator.validate(event: event)
        switch result {
        case .accept(let s):
            isRecording = false
            setRecordingAppearance(false)
            delegate?.shortcutRecorderDidRecord(s)
        case .escape:
            isRecording = false
            setRecordingAppearance(false)
            window?.makeFirstResponder(nil)
            delegate?.shortcutRecorderDidCancel()
        case .reject:
            NSSound.beep()
            delegate?.shortcutRecorderDidReject()
        case .tab:
            window?.makeFirstResponder(nil)
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        if isRecording { updateDisplay() }
    }

    private func updateDisplay() {
        if isRecording {
            displayField.stringValue = "Type shortcut\u{2026}"
        } else {
            displayField.stringValue = shortcut.displayString
        }
        setAccessibilityValue(displayField.stringValue)
    }

    private func setRecordingAppearance(_ recording: Bool) {
        layer?.borderColor = recording ? NSColor.keyboardFocusIndicatorColor.cgColor : NSColor.separatorColor.cgColor
        layer?.borderWidth = recording ? 2 : 1
    }
}
