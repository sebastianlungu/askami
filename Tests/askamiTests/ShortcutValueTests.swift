import Testing
import Carbon
@testable import askami

@Test("default shortcut is Control-Option-Space")
func defaultShortcut() {
    #expect(ShortcutValue.default.keyCode == UInt32(kVK_Space))
    #expect(ShortcutValue.default.modifiers == (UInt32(controlKey) | UInt32(optionKey)))
}

@Test("valid shortcut requires at least one modifier")
func validRequiresModifier() {
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Space), modifiers: 0).isValid)
}

@Test("valid shortcut rejects modifier-only key")
func validRejectsModifierOnly() {
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Control), modifiers: UInt32(controlKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Option), modifiers: UInt32(optionKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Shift), modifiers: UInt32(shiftKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_RightShift), modifiers: UInt32(shiftKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_RightCommand), modifiers: UInt32(cmdKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_Function), modifiers: UInt32(controlKey)).isValid)
    #expect(!ShortcutValue(keyCode: UInt32(kVK_CapsLock), modifiers: UInt32(shiftKey)).isValid)
}

@Test("Control plus key is valid")
func controlPlusKeyValid() {
    #expect(ShortcutValue(keyCode: 12, modifiers: UInt32(controlKey)).isValid)
}

@Test("Command-Shift plus key is valid")
func commandShiftPlusKeyValid() {
    #expect(ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey) | UInt32(shiftKey)).isValid)
}

@Test("any single modifier plus key is valid")
func anySingleModifierPlusKeyValid() {
    let mods: [UInt32] = [UInt32(controlKey), UInt32(optionKey), UInt32(shiftKey), UInt32(cmdKey)]
    for m in mods {
        #expect(ShortcutValue(keyCode: 12, modifiers: m).isValid)
    }
}

@Test("ShortcutValue is Sendable")
func shortcutSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}
    assertSendable(ShortcutValue.self)
}

@Test("ShortcutValue is Equatable")
func shortcutEquatable() {
    let a = ShortcutValue(keyCode: 1, modifiers: 2)
    let b = ShortcutValue(keyCode: 1, modifiers: 2)
    let c = ShortcutValue(keyCode: 3, modifiers: 4)
    #expect(a == b)
    #expect(a != c)
}

// MARK: - Multi-Modifier Combinations

@Test("Control-Option plus Space is valid")
func controlOptionPlusSpaceValid() {
    #expect(ShortcutValue(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey) | UInt32(optionKey)).isValid)
}

@Test("Control-Shift plus letter is valid")
func controlShiftPlusLetterValid() {
    #expect(ShortcutValue(keyCode: 0, modifiers: UInt32(controlKey) | UInt32(shiftKey)).isValid)
}

@Test("Control-Command plus function key is valid")
func controlCommandPlusFunctionKeyValid() {
    #expect(ShortcutValue(keyCode: UInt32(kVK_F1), modifiers: UInt32(controlKey) | UInt32(cmdKey)).isValid)
}

@Test("Option-Command plus arrow key is valid")
func optionCommandPlusArrowKeyValid() {
    #expect(ShortcutValue(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey) | UInt32(cmdKey)).isValid)
}

@Test("Option-Shift plus key is valid")
func optionShiftPlusKeyValid() {
    #expect(ShortcutValue(keyCode: 12, modifiers: UInt32(optionKey) | UInt32(shiftKey)).isValid)
}

@Test("Shift-Command plus key is valid")
func shiftCommandPlusKeyValid() {
    #expect(ShortcutValue(keyCode: 12, modifiers: UInt32(shiftKey) | UInt32(cmdKey)).isValid)
}

@Test("All four modifiers plus key is valid")
func allFourModifiersPlusKeyValid() {
    let all = UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
    #expect(ShortcutValue(keyCode: 12, modifiers: all).isValid)
}

// MARK: - Display String

@Test("default display string shows Control-Option-Space")
func defaultDisplayString() {
    #expect(ShortcutValue.default.displayString == "\u{2303}\u{2325}Space")
}

@Test("display string shows Control-Command-A")
func displayControlCommandA() {
    let s = ShortcutValue(keyCode: 0, modifiers: UInt32(controlKey) | UInt32(cmdKey))
    #expect(s.displayString == "\u{2303}\u{2318}A")
}

@Test("display string shows Shift-Command-F1")
func displayShiftCommandF1() {
    let s = ShortcutValue(keyCode: UInt32(kVK_F1), modifiers: UInt32(shiftKey) | UInt32(cmdKey))
    #expect(s.displayString == "\u{21E7}\u{2318}F1")
}

@Test("display string F1 through F16")
func displayAllFunctionKeys() {
    let map: [(UInt32, String)] = [
        (UInt32(kVK_F1), "F1"), (UInt32(kVK_F2), "F2"),
        (UInt32(kVK_F3), "F3"), (UInt32(kVK_F4), "F4"),
        (UInt32(kVK_F5), "F5"), (UInt32(kVK_F6), "F6"),
        (UInt32(kVK_F7), "F7"), (UInt32(kVK_F8), "F8"),
        (UInt32(kVK_F9), "F9"), (UInt32(kVK_F10), "F10"),
        (UInt32(kVK_F11), "F11"), (UInt32(kVK_F12), "F12"),
        (UInt32(kVK_F13), "F13"), (UInt32(kVK_F14), "F14"),
        (UInt32(kVK_F15), "F15"), (UInt32(kVK_F16), "F16"),
    ]
    for (kc, expected) in map {
        let s = ShortcutValue(keyCode: kc, modifiers: UInt32(controlKey))
        #expect(s.displayString.hasSuffix(expected), "F-key \(expected): got \(s.displayString)")
    }
}

@Test("display string shows Option-Shift-UpArrow")
func displayOptionShiftUpArrow() {
    let s = ShortcutValue(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey) | UInt32(shiftKey))
    #expect(s.displayString == "\u{2325}\u{21E7}\u{2191}")
}

// MARK: - Validator Multi-Modifier

@Test("validator accepts Control-Option-A")
func validatorAcceptControlOptionA() {
    let result = ShortcutInputValidator.validate(keyCode: 0, modifierFlags: [.control, .option])
    guard case .accept(let s) = result else { return #expect(Bool(false), "expected accept") }
    #expect(s.modifiers == (UInt32(controlKey) | UInt32(optionKey)))
}

@Test("validator accepts Control-Shift-F1")
func validatorAcceptControlShiftF1() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_F1), modifierFlags: [.control, .shift])
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}

@Test("validator accepts Option-Command-UpArrow")
func validatorAcceptOptionCommandUpArrow() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_UpArrow), modifierFlags: [.option, .command])
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}

@Test("validator accepts Shift-Command-DownArrow")
func validatorAcceptShiftCommandDownArrow() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_DownArrow), modifierFlags: [.shift, .command])
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}
