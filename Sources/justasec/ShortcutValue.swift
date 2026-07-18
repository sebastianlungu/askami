import Carbon
import AppKit

public struct ShortcutValue: Sendable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let `default` = ShortcutValue(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey) | UInt32(optionKey)
    )

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isValid: Bool {
        let hasModifier = (modifiers & (UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey))) != 0
        let isModifierKey = modifierKeyCodes.contains(keyCode)
        return hasModifier && !isModifierKey
    }

    public var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { result += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { result += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0 { result += "\u{2318}" }
        result += keyCodeDisplayName
        return result
    }

    private var keyCodeDisplayName: String {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Delete): return "\u{232B}"
        case UInt32(kVK_Tab): return "\u{21E5}"
        case UInt32(kVK_Return): return "\u{21A9}"
        case UInt32(kVK_Escape): return "\u{238B}"
        case UInt32(kVK_ForwardDelete): return "\u{2326}"
        case UInt32(kVK_UpArrow): return "\u{2191}"
        case UInt32(kVK_DownArrow): return "\u{2193}"
        case UInt32(kVK_LeftArrow): return "\u{2190}"
        case UInt32(kVK_RightArrow): return "\u{2192}"
        case UInt32(kVK_Help): return "Help"
        case UInt32(kVK_Home): return "\u{2196}"
        case UInt32(kVK_End): return "\u{2198}"
        case UInt32(kVK_PageUp): return "\u{21DE}"
        case UInt32(kVK_PageDown): return "\u{21DF}"
        case let f where f >= UInt32(kVK_F1) && f <= UInt32(kVK_F16):
            return "F\(f - UInt32(kVK_F1) + 1)"
        default:
            return charForKeyCode(keyCode) ?? "?"
        }
    }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
}

private let modifierKeyCodes: Set<UInt32> = [
    UInt32(kVK_Control), UInt32(kVK_Option), UInt32(kVK_RightOption),
    UInt32(kVK_Shift), UInt32(kVK_RightShift),
    UInt32(kVK_Command), UInt32(kVK_RightCommand),
    UInt32(kVK_CapsLock), UInt32(kVK_Function),
]

private func charForKeyCode(_ code: UInt32) -> String? {
    let maxLen = 4
    var deadKeys: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: maxLen)
    var actualLen = 0
    let layoutPtr = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
    let layoutDataPtr = TISGetInputSourceProperty(layoutPtr, kTISPropertyUnicodeKeyLayoutData)
    guard let layoutData = layoutDataPtr else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
        guard let baseAddr = bytes.baseAddress else { return -1 }
        let layout = baseAddr.assumingMemoryBound(to: UCKeyboardLayout.self)
        return UCKeyTranslate(
            layout, UInt16(code), UInt16(kUCKeyActionDisplay),
            0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeys, maxLen, &actualLen, &chars
        )
    }
    guard status == noErr else { return nil }
    return String(utf16CodeUnits: chars, count: actualLen).uppercased()
}
