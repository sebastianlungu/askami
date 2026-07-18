import AppKit

@MainActor
public final class SettingsPanelController: NSObject {
    public let window: NSWindow
    public let recorderView: ShortcutRecorderView
    public let quitButton: NSButton
    public let errorLabel: NSTextField

    private let onReplace: (ShortcutValue) -> Bool
    private var shortcutBeforeRecording: ShortcutValue

    public init(
        initialShortcut: ShortcutValue,
        onReplace: @escaping (ShortcutValue) -> Bool,
        onTerminate: @escaping () -> Void
    ) {
        self.onReplace = onReplace
        self.shortcutBeforeRecording = initialShortcut

        let contentRect = NSRect(x: 0, y: 0, width: 320, height: 140)
        window = NSWindow(contentRect: contentRect, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "JustASec"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(contentRect.size)

        recorderView = ShortcutRecorderView(shortcut: initialShortcut)

        quitButton = NSButton(title: "Quit JustASec", target: nil, action: nil)
        quitButton.bezelStyle = .push
        quitButton.setAccessibilityLabel("Quit JustASec")

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        errorLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.isHidden = true
        errorLabel.setAccessibilityLabel("Shortcut registration error")

        super.init()

        window.delegate = self
        recorderView.delegate = self
        quitButton.target = self
        quitButton.action = #selector(quitAction)
        setupLayout()
    }

    @objc public func quitAction() {
        NSApp.terminate(nil)
    }

    public func showPanel() {
        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func closePanel() {
        window.orderOut(nil)
    }

    public func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    public func hideError() {
        errorLabel.isHidden = true
        errorLabel.stringValue = ""
    }

    public func updateDisplayedShortcut(_ shortcut: ShortcutValue) {
        recorderView.updateShortcut(shortcut)
    }

    private func setupLayout() {
        let contentView = window.contentView!

        let shortcutLabel = NSTextField(labelWithString: "Global Shortcut")
        shortcutLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.setAccessibilityLabel("Global Shortcut label")

        for v in [shortcutLabel, recorderView, errorLabel, quitButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        let m: CGFloat = 16
        let g: CGFloat = 6

        NSLayoutConstraint.activate([
            shortcutLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: m),
            shortcutLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: m),
            shortcutLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -m),

            recorderView.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: g),
            recorderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: m),
            recorderView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -m),

            errorLabel.topAnchor.constraint(equalTo: recorderView.bottomAnchor, constant: g),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: m),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -m),

            quitButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -m),
            quitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -m),
        ])
    }
}

extension SettingsPanelController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        closePanel()
    }
}

extension SettingsPanelController: ShortcutRecorderDelegate {
    public func shortcutRecorderDidRecord(_ shortcut: ShortcutValue) {
        hideError()
        if onReplace(shortcut) {
            recorderView.updateShortcut(shortcut)
            shortcutBeforeRecording = shortcut
        } else {
            showError("Shortcut cannot be registered. Try a different combination.")
            recorderView.updateShortcut(shortcutBeforeRecording)
        }
    }

    public func shortcutRecorderDidCancel() {
        recorderView.updateShortcut(shortcutBeforeRecording)
        hideError()
    }

    public func shortcutRecorderDidReject() {}
}
