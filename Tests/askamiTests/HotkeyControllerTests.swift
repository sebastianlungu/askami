import Testing
@testable import askami

@Test("register does not crash in test environment")
func registerNoCrash() {
    let controller = HotkeyController(handler: {})
    controller.register()
}

@Test("unregister after register does not crash")
func unregisterNoCrash() {
    let controller = HotkeyController(handler: {})
    controller.register()
    controller.unregister()
}

@Test("register after unregister does not crash")
func registerAfterUnregisterNoCrash() {
    let controller = HotkeyController(handler: {})
    controller.register()
    controller.unregister()
    controller.register()
}

@Test("double register does not crash")
func doubleRegisterNoCrash() {
    let controller = HotkeyController(handler: {})
    controller.register()
    controller.register()
}

@Test("deinit after register does not crash")
func deinitAfterRegisterNoCrash() {
    var controller: HotkeyController? = HotkeyController(handler: {})
    controller?.register()
    controller = nil
}

@Test("deinit without register does not crash")
func deinitWithoutRegisterNoCrash() {
    _ = HotkeyController(handler: {})
}
