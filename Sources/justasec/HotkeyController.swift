import Carbon

public final class HotkeyController {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callbackContext: UnsafeMutableRawPointer?
    fileprivate let handler: @Sendable () -> Void

    public init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    deinit {
        unregister()
    }

    @discardableResult
    public func register() -> Bool {
        guard hotkeyRef == nil else { return true }

        let keyCode = UInt32(kVK_Space)
        let modifiers = UInt32(controlKey) | UInt32(optionKey)
        let hotKeyID = EventHotKeyID(signature: 0x4A534543, id: 1)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetEventDispatcherTarget(), 0, &ref
        )

        guard status == noErr, let ref else { return false }
        hotkeyRef = ref

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        var handlerRef: EventHandlerRef?

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyCallback,
            1, &eventType, selfPtr, &handlerRef
        )

        guard installStatus == noErr else {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
            Unmanaged<HotkeyController>.fromOpaque(selfPtr).release()
            return false
        }

        callbackContext = selfPtr
        eventHandlerRef = handlerRef
        return true
    }

    public func unregister() {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        if let ctx = callbackContext {
            Unmanaged<HotkeyController>.fromOpaque(ctx).release()
            callbackContext = nil
        }
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }
}

private let hotkeyCallback: EventHandlerProcPtr = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.handler()
    return noErr
}
