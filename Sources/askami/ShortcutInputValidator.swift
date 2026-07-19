import Carbon
import AppKit

public struct ShortcutInputValidator: Sendable {
    public enum Result: Equatable, Sendable {
        case accept(ShortcutValue)
        case escape
        case reject
        case tab
    }

    public static func validate(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Result {
        if Int(keyCode) == kVK_Escape { return .escape }

        if Int(keyCode) == kVK_Tab && modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            return .tab
        }

        let mods = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasStandard = mods.contains(.control) || mods.contains(.option) || mods.contains(.shift) || mods.contains(.command)

        guard hasStandard else { return .reject }

        let modKeyCodes: Set<UInt16> = [
            UInt16(kVK_Control), UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_CapsLock), UInt16(kVK_Function),
        ]
        guard !modKeyCodes.contains(keyCode) else { return .reject }

        var carbonMods: UInt32 = 0
        if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
        if mods.contains(.option) { carbonMods |= UInt32(optionKey) }
        if mods.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }

        return .accept(ShortcutValue(keyCode: UInt32(keyCode), modifiers: carbonMods))
    }

    public static func validate(event: NSEvent) -> Result {
        validate(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }
}
