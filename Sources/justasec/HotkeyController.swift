import Carbon

public final class HotkeyController {
    private let handler: @Sendable () -> Void
    private let registrar: CarbonHotkeyRegistrarProtocol
    private let preferenceStore: ShortcutPreferenceStoreProtocol
    private var activeToken: HotkeyRegistrationToken?
    private var hasEmittedDiagnostic = false

    public private(set) var currentShortcut: ShortcutValue

    public init(
        handler: @escaping @Sendable () -> Void,
        registrar: CarbonHotkeyRegistrarProtocol = RealCarbonHotkeyRegistrar(),
        preferenceStore: ShortcutPreferenceStoreProtocol = RealShortcutPreferenceStore()
    ) {
        self.handler = handler
        self.registrar = registrar
        self.preferenceStore = preferenceStore
        switch preferenceStore.loadShortcut() {
        case .missing:
            self.currentShortcut = .default
        case .valid(let s):
            self.currentShortcut = s
        case .malformed:
            self.currentShortcut = .default
            fputs("justasec: hotkey preference data invalid, using default\n", stderr)
        }
    }

    deinit {
        if let token = activeToken { registrar.cancel(token) }
    }

    @discardableResult
    public func register() -> Bool {
        if activeToken != nil { return true }

        if !currentShortcut.isValid {
            currentShortcut = .default
        }

        if let token = registrar.register(keyCode: currentShortcut.keyCode, modifiers: currentShortcut.modifiers, handler: handler) {
            activeToken = token
            preferenceStore.saveShortcut(currentShortcut)
            return true
        }

        if currentShortcut != .default {
            currentShortcut = .default
            if let token = registrar.register(keyCode: ShortcutValue.default.keyCode, modifiers: ShortcutValue.default.modifiers, handler: handler) {
                activeToken = token
                preferenceStore.saveShortcut(.default)
                fputs("justasec: hotkey fallback to Control-Option-Space\n", stderr)
                return true
            }
        }

        return false
    }

    @discardableResult
    public func replaceShortcut(with newShortcut: ShortcutValue) -> Bool {
        guard newShortcut.isValid else { return false }
        guard newShortcut != currentShortcut else { return true }

        guard let candidate = registrar.register(keyCode: newShortcut.keyCode, modifiers: newShortcut.modifiers, handler: handler) else {
            return false
        }

        if let old = activeToken { registrar.cancel(old) }
        activeToken = candidate
        currentShortcut = newShortcut
        preferenceStore.saveShortcut(newShortcut)
        return true
    }

    public func unregister() {
        if let token = activeToken { registrar.cancel(token); activeToken = nil }
    }
}
