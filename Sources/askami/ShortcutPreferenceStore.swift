import Foundation
import Carbon

public enum ShortcutLoadResult: Sendable, Equatable {
    case missing
    case valid(ShortcutValue)
    case malformed
}

public protocol ShortcutPreferenceStoreProtocol: AnyObject {
    func loadShortcut() -> ShortcutLoadResult
    func saveShortcut(_ shortcut: ShortcutValue)
}

public final class RealShortcutPreferenceStore: ShortcutPreferenceStoreProtocol {
    private let defaults: UserDefaults
    private let keyCodeKey = "askami_hotkey_key_code"
    private let modifiersKey = "askami_hotkey_modifiers"

    public init(suiteName: String? = nil) {
        if let suiteName {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.defaults = .standard
        }
    }

    public func loadShortcut() -> ShortcutLoadResult {
        guard let keyCodeObj = defaults.object(forKey: keyCodeKey) else { return .missing }
        guard let modifiersObj = defaults.object(forKey: modifiersKey) else { return .malformed }

        guard let keyCodeInt = keyCodeObj as? Int,
              let modifiersInt = modifiersObj as? Int
        else { return .malformed }

        guard keyCodeInt >= 0, modifiersInt >= 0 else { return .malformed }

        let keyCode = UInt32(keyCodeInt)
        let modifiers = UInt32(modifiersInt)

        guard keyCode <= 128 else { return .malformed }

        let standardMods = UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        guard modifiers & ~standardMods == 0 else { return .malformed }

        let shortcut = ShortcutValue(keyCode: keyCode, modifiers: modifiers)
        guard shortcut.isValid else { return .malformed }
        return .valid(shortcut)
    }

    public func saveShortcut(_ shortcut: ShortcutValue) {
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
        defaults.set(Int(shortcut.modifiers), forKey: modifiersKey)
    }
}
