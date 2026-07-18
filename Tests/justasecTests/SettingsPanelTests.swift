import Testing
import Foundation
import AppKit
import Carbon
@testable import justasec

// MARK: - Test Doubles

final class TestCarbonHotkeyRegistrar: CarbonHotkeyRegistrarProtocol {
    private(set) var tokens: [HotkeyRegistrationToken] = []
    private(set) var cancelledTokens: [HotkeyRegistrationToken] = []
    private(set) var lastKeyCode: UInt32?
    private(set) var lastModifiers: UInt32?
    private(set) var lastHandler: (@Sendable () -> Void)?
    var shouldSucceed = true
    private var nextID: UInt64 = 1

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable () -> Void) -> HotkeyRegistrationToken? {
        guard shouldSucceed else { return nil }
        lastKeyCode = keyCode
        lastModifiers = modifiers
        lastHandler = handler
        let token = HotkeyRegistrationToken(id: nextID)
        nextID += 1
        tokens.append(token)
        return token
    }

    func cancel(_ token: HotkeyRegistrationToken) {
        guard tokens.contains(token) else { return }
        cancelledTokens.append(token)
        tokens.removeAll { $0 == token }
    }
}
final class TestShortcutPreferenceStore: ShortcutPreferenceStoreProtocol {
    var loadResult: ShortcutLoadResult = .missing
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var savedValues: [ShortcutValue] = []

    func loadShortcut() -> ShortcutLoadResult {
        loadCount += 1
        return loadResult
    }

    func saveShortcut(_ shortcut: ShortcutValue) {
        saveCount += 1
        savedValues.append(shortcut)
    }
}

// MARK: - ShortcutInputValidator Tests

@Test("validator accepts Control-Space")
func validatorAcceptControlSpace() {
    let mods: NSEvent.ModifierFlags = [.control]
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: mods)
    guard case .accept(let s) = result else { return #expect(Bool(false), "expected accept") }
    #expect(s.keyCode == UInt32(kVK_Space))
    #expect(s.modifiers == UInt32(controlKey))
}

@Test("validator accepts Option-Space")
func validatorAcceptOptionSpace() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: [.option])
    guard case .accept(let s) = result else { return #expect(Bool(false), "expected accept") }
    #expect(s.modifiers == UInt32(optionKey))
}

@Test("validator accepts Shift-Space")
func validatorAcceptShiftSpace() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: [.shift])
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}

@Test("validator accepts Command-Space")
func validatorAcceptCommandSpace() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: [.command])
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}

@Test("validator accepts multi-modifier combination")
func validatorAcceptMultiModifier() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: [.control, .option, .shift, .command])
    guard case .accept(let s) = result else { return #expect(Bool(false), "expected accept") }
    #expect(s.modifiers == UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey))
}

@Test("validator rejects bare key")
func validatorRejectBareKey() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Space), modifierFlags: [])
    #expect(result == .reject)
}

@Test("validator rejects modifier-only key")
func validatorRejectModifierOnly() {
    #expect(ShortcutInputValidator.validate(keyCode: UInt16(kVK_Control), modifierFlags: [.control]) == .reject)
    #expect(ShortcutInputValidator.validate(keyCode: UInt16(kVK_Option), modifierFlags: [.option]) == .reject)
    #expect(ShortcutInputValidator.validate(keyCode: UInt16(kVK_Shift), modifierFlags: [.shift]) == .reject)
    #expect(ShortcutInputValidator.validate(keyCode: UInt16(kVK_Command), modifierFlags: [.command]) == .reject)
}

@Test("validator escape returns escape")
func validatorEscape() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Escape), modifierFlags: [])
    #expect(result == .escape)
}

@Test("validator tab without modifiers returns tab")
func validatorTab() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Tab), modifierFlags: [])
    #expect(result == .tab)
}

@Test("validator tab with modifier is accept")
func validatorTabWithModifier() {
    let result = ShortcutInputValidator.validate(keyCode: UInt16(kVK_Tab), modifierFlags: [.control])
    #expect(result != .tab)
    guard case .accept = result else { return #expect(Bool(false), "expected accept") }
}

// MARK: - RealShortcutPreferenceStore Tests

@Test("preference store returns missing when empty")
func prefsMissingWhenEmpty() {
    let uuid = UUID().uuidString
    let store = RealShortcutPreferenceStore(suiteName: uuid)
    #expect(store.loadShortcut() == .missing)
}

@Test("preference store save and load round-trip")
func prefsSaveAndLoad() {
    let uuid = UUID().uuidString
    let store = RealShortcutPreferenceStore(suiteName: uuid)
    let shortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
    store.saveShortcut(shortcut)
    #expect(store.loadShortcut() == .valid(shortcut))
}

@Test("preference store returns malformed for non-Int key code")
func prefsMalformedKeyCodeType() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set("bad", forKey: "justasec_hotkey_key_code")
    d.set(Int(123), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for non-Int modifiers")
func prefsMalformedModifiersType() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(12), forKey: "justasec_hotkey_key_code")
    d.set("bad", forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for negative key code")
func prefsMalformedNegativeKeyCode() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(-1), forKey: "justasec_hotkey_key_code")
    d.set(Int(123), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for negative modifiers")
func prefsMalformedNegativeModifiers() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(12), forKey: "justasec_hotkey_key_code")
    d.set(Int(-5), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for oversized key code")
func prefsMalformedOversizedKeyCode() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(200), forKey: "justasec_hotkey_key_code")
    d.set(Int(123), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for unknown modifier bits")
func prefsMalformedUnknownModifierBits() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(12), forKey: "justasec_hotkey_key_code")
    d.set(Int(0xFF00), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for no-standard-modifier shortcut")
func prefsMalformedMissingModifier() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(12), forKey: "justasec_hotkey_key_code")
    d.set(Int(0), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store returns malformed for modifier-only shortcut")
func prefsMalformedModifierOnly() {
    let uuid = UUID().uuidString
    let d = UserDefaults(suiteName: uuid)!
    d.set(Int(kVK_Control), forKey: "justasec_hotkey_key_code")
    d.set(Int(controlKey), forKey: "justasec_hotkey_modifiers")
    #expect(RealShortcutPreferenceStore(suiteName: uuid).loadShortcut() == .malformed)
}

@Test("preference store persists only standard modifier bits")
func prefsPersistsStandardModifiers() {
    let uuid = UUID().uuidString
    let store = RealShortcutPreferenceStore(suiteName: uuid)
    let shortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(controlKey) | UInt32(cmdKey))
    store.saveShortcut(shortcut)
    #expect(store.loadShortcut() == .valid(shortcut))
}

// MARK: - HotkeyController Tests

@Test("HotkeyController uses default when prefs missing")
@MainActor
func hotkeyMissingPrefsDefaults() {
    let prefs = TestShortcutPreferenceStore()
    prefs.loadResult = .missing
    let ctrl = HotkeyController(handler: {}, registrar: TestCarbonHotkeyRegistrar(), preferenceStore: prefs)
    #expect(ctrl.currentShortcut == .default)
}

@Test("HotkeyController uses valid shortcut from prefs")
@MainActor
func hotkeyValidPrefs() {
    let prefs = TestShortcutPreferenceStore()
    let s = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey))
    prefs.loadResult = .valid(s)
    let ctrl = HotkeyController(handler: {}, registrar: TestCarbonHotkeyRegistrar(), preferenceStore: prefs)
    #expect(ctrl.currentShortcut == s)
}

@Test("HotkeyController uses default and no crash when prefs malformed")
@MainActor
func hotkeyMalformedPrefsDefaults() {
    let prefs = TestShortcutPreferenceStore()
    prefs.loadResult = .malformed
    let ctrl = HotkeyController(handler: {}, registrar: TestCarbonHotkeyRegistrar(), preferenceStore: prefs)
    #expect(ctrl.currentShortcut == .default)
}

@Test("HotkeyController register delegates to registrar")
@MainActor
func hotkeyRegisterDelegates() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    let result = ctrl.register()
    #expect(result)
    #expect(registrar.lastKeyCode == ShortcutValue.default.keyCode)
    #expect(registrar.lastModifiers == ShortcutValue.default.modifiers)
}

@Test("HotkeyController register saves to prefs on success")
@MainActor
func hotkeyRegisterSaves() {
    let prefs = TestShortcutPreferenceStore()
    let ctrl = HotkeyController(handler: {}, registrar: TestCarbonHotkeyRegistrar(), preferenceStore: prefs)
    ctrl.register()
    #expect(prefs.saveCount == 1)
}

@Test("HotkeyController register returns false when registrar fails")
@MainActor
func hotkeyRegisterFailReturnsFalse() {
    let registrar = TestCarbonHotkeyRegistrar()
    registrar.shouldSucceed = false
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    let result = ctrl.register()
    #expect(!result)
}

@Test("HotkeyController register is idempotent")
@MainActor
func hotkeyRegisterIdempotent() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    let tokenCount = registrar.tokens.count
    ctrl.register()
    #expect(registrar.tokens.count == tokenCount)
}

@Test("HotkeyController replaceShortcut same value is no-op success")
@MainActor
func hotkeyReplaceSameValueNoOp() {
    let registrar = TestCarbonHotkeyRegistrar()
    let prefs = TestShortcutPreferenceStore()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: prefs)
    ctrl.register()
    let tokenCount = registrar.tokens.count
    let saveCount = prefs.saveCount
    let result = ctrl.replaceShortcut(with: ctrl.currentShortcut)
    #expect(result)
    #expect(registrar.tokens.count == tokenCount)
    #expect(prefs.saveCount == saveCount)
}

@Test("HotkeyController replaceShortcut candidate live before old cancel")
@MainActor
func hotkeyReplaceCandidateBeforeOldCancel() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    let oldToken = registrar.tokens.last

    let newShortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey))
    let result = ctrl.replaceShortcut(with: newShortcut)
    #expect(result)
    #expect(registrar.tokens.count == 1)
    #expect(registrar.cancelledTokens.count == 1)
    #expect(registrar.cancelledTokens.first == oldToken)
    #expect(registrar.tokens.first != oldToken)
}

@Test("HotkeyController replaceShortcut preserves old on failure")
@MainActor
func hotkeyReplacePreservesOldOnFailure() {
    let registrar = TestCarbonHotkeyRegistrar()
    let prefs = TestShortcutPreferenceStore()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: prefs)
    ctrl.register()
    let oldShortcut = ctrl.currentShortcut

    registrar.shouldSucceed = false
    let result = ctrl.replaceShortcut(with: ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey)))
    #expect(!result)
    #expect(ctrl.currentShortcut == oldShortcut)
    #expect(registrar.cancelledTokens.isEmpty)
}

@Test("HotkeyController replaceShortcut persists on success")
@MainActor
func hotkeyReplacePersists() {
    let prefs = TestShortcutPreferenceStore()
    let ctrl = HotkeyController(handler: {}, registrar: TestCarbonHotkeyRegistrar(), preferenceStore: prefs)
    ctrl.register()
    let newShortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey))
    ctrl.replaceShortcut(with: newShortcut)
    #expect(prefs.savedValues.last == newShortcut)
}

@Test("HotkeyController replaceShortcut rejects invalid")
@MainActor
func hotkeyReplaceRejectsInvalid() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    let oldShortcut = ctrl.currentShortcut
    let invalid = ShortcutValue(keyCode: 12, modifiers: 0)
    #expect(!ctrl.replaceShortcut(with: invalid))
    #expect(ctrl.currentShortcut == oldShortcut)
    #expect(registrar.cancelledTokens.isEmpty)
}

@Test("HotkeyController repeated replaceShortcut maintains registration")
@MainActor
func hotkeyReplaceRepeated() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()

    for i in 0..<3 {
        let s = ShortcutValue(keyCode: UInt32(20 + i), modifiers: UInt32(controlKey))
        let result = ctrl.replaceShortcut(with: s)
        #expect(result)
        #expect(ctrl.currentShortcut == s)
    }
    #expect(registrar.tokens.count == 1)
    #expect(registrar.cancelledTokens.count == 3)
}

@Test("HotkeyController unregister cancels active token")
@MainActor
func hotkeyUnregisterCancelsToken() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    #expect(!registrar.cancelledTokens.isEmpty == false) // not cancelled yet
    ctrl.unregister()
    #expect(registrar.cancelledTokens.count == 1)
}

@Test("HotkeyController unregister is idempotent")
@MainActor
func hotkeyUnregisterIdempotent() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    ctrl.unregister()
    ctrl.unregister()
    #expect(registrar.cancelledTokens.count == 1)
}

@Test("HotkeyController handler is called when registrar fires")
@MainActor
func hotkeyHandlerCalled() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: { Task { @MainActor in } }, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    #expect(registrar.lastHandler != nil)
}

@Test("HotkeyController token cancel is idempotent on registrar")
@MainActor
func tokenCancelIdempotent() {
    let registrar = TestCarbonHotkeyRegistrar()
    let ctrl = HotkeyController(handler: {}, registrar: registrar, preferenceStore: TestShortcutPreferenceStore())
    ctrl.register()
    let token = registrar.tokens[0]
    registrar.cancel(token)
    registrar.cancel(token)
    #expect(registrar.cancelledTokens.filter { $0 == token }.count == 1)
}

// MARK: - ShortcutRecorderView Tests

@Test("ShortcutRecorderView displays current shortcut string")
@MainActor
func recorderDisplaysShortcut() {
    let recorder = ShortcutRecorderView(shortcut: .default)
    #expect(recorder.shortcut == .default)
}

@Test("ShortcutRecorderView updates displayed shortcut")
@MainActor
func recorderUpdatesShortcut() {
    let recorder = ShortcutRecorderView(shortcut: .default)
    let newShortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey))
    recorder.updateShortcut(newShortcut)
    #expect(recorder.shortcut == newShortcut)
}

@Test("ShortcutRecorderView is in tab order")
@MainActor
func recorderIsInTabOrder() {
    let recorder = ShortcutRecorderView(shortcut: .default)
    #expect(recorder.acceptsFirstResponder)
    #expect(recorder.canBecomeKeyView)
}

@Test("ShortcutRecorderView has accessibility label and role")
@MainActor
func recorderHasAccessibility() {
    let recorder = ShortcutRecorderView(shortcut: .default)
    #expect(recorder.accessibilityLabel() != nil)
    #expect(recorder.accessibilityRole() == .button)
}

// MARK: - SettingsPanelController Tests

@Test("SettingsPanelController window is non-resizable")
@MainActor
func panelNonResizable() {
    let ctrl = makePanel()
    #expect(!ctrl.window.styleMask.contains(NSWindow.StyleMask.resizable))
}

@Test("SettingsPanelController close hides does not quit")
@MainActor
func panelCloseHidesOnly() {
    let ctrl = makePanel()
    ctrl.showPanel()
    #expect(ctrl.window.isVisible)
    ctrl.closePanel()
    #expect(!ctrl.window.isVisible)
}

@Test("SettingsPanelController contains error label hidden by default")
@MainActor
func panelHasHiddenErrorLabel() {
    #expect(makePanel().errorLabel.isHidden)
}

@Test("SettingsPanelController error label shown when set")
@MainActor
func panelShowErrorLabel() {
    let ctrl = makePanel()
    ctrl.showError("Test error")
    #expect(!ctrl.errorLabel.isHidden)
    #expect(ctrl.errorLabel.stringValue == "Test error")
    ctrl.hideError()
    #expect(ctrl.errorLabel.isHidden)
}

@Test("SettingsPanelController singleton reopen focuses existing")
@MainActor
func panelSingletonReopenFocuses() {
    let ctrl = makePanel()
    ctrl.showPanel()
    let w1 = ctrl.window
    ctrl.showPanel()
    #expect(ctrl.window === w1)
    ctrl.closePanel()
}

@Test("SettingsPanelController restore old display on replace failure")
@MainActor
func panelRestoreOnFailure() {
    let recorderShortcut = ShortcutValue(keyCode: 5, modifiers: UInt32(controlKey))
    let ctrl = SettingsPanelController(
        initialShortcut: recorderShortcut,
        onReplace: { _ in false },
        onTerminate: {}
    )
    ctrl.shortcutRecorderDidRecord(ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey)))
    #expect(!ctrl.errorLabel.isHidden)
    #expect(ctrl.recorderView.shortcut == recorderShortcut)
}

@Test("SettingsPanelController update display on replace success")
@MainActor
func panelUpdateOnSuccess() {
    let ctrl = SettingsPanelController(
        initialShortcut: .default,
        onReplace: { _ in true },
        onTerminate: {}
    )
    let newShortcut = ShortcutValue(keyCode: 12, modifiers: UInt32(cmdKey))
    ctrl.shortcutRecorderDidRecord(newShortcut)
    #expect(ctrl.errorLabel.isHidden)
    #expect(ctrl.recorderView.shortcut == newShortcut)
}

@Test("SettingsPanelController cancel restores display")
@MainActor
func panelCancelRestores() {
    let ctrl = SettingsPanelController(
        initialShortcut: .default,
        onReplace: { _ in true },
        onTerminate: {}
    )
    ctrl.shortcutRecorderDidCancel()
    #expect(ctrl.recorderView.shortcut == .default)
    #expect(ctrl.errorLabel.isHidden)
}

@Test("SettingsPanelController quit button calls NSApp.terminate")
@MainActor
func panelQuitButtonAction() {
    let ctrl = makePanel()
    #expect(ctrl.quitButton.action == #selector(SettingsPanelController.quitAction))
    #expect(ctrl.quitButton.target === ctrl)
}

// MARK: - Menu Tests

@Test("JustasecApp sets up menu with Cmd-Q Quit item")
@MainActor
func appMenuHasCmdQ() {
    let app = JustasecApp()
    app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification, object: nil))

    let mainMenu = NSApp.mainMenu
    #expect(mainMenu != nil)
    let appMenuItem = mainMenu?.item(at: 0)
    #expect(appMenuItem != nil)
    let appMenu = appMenuItem?.submenu
    #expect(appMenu != nil)
    let quitItem = appMenu?.item(at: 0)
    #expect(quitItem != nil)
    #expect(quitItem?.keyEquivalent == "q")
    #expect(quitItem?.keyEquivalentModifierMask == .command)
    #expect(quitItem?.action == #selector(NSApp.terminate(_:)))
}

// MARK: - JustasecApp Panel Wiring Tests

@Test("JustasecApp settingsPanelController is accessible")
@MainActor
func appHasSettingsPanel() {
    let app = JustasecApp()
    // Force lazy init
    _ = app.settingsPanelController
}

// MARK: - Helpers

@MainActor
private func makePanel() -> SettingsPanelController {
    SettingsPanelController(
        initialShortcut: .default,
        onReplace: { _ in true },
        onTerminate: {}
    )
}
