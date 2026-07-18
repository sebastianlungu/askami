import Testing
import Carbon
@testable import justasec

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
