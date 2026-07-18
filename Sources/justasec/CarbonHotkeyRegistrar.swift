import Carbon
import os.lock

public struct HotkeyRegistrationToken: Sendable, Equatable {
    let id: UInt64
}

public protocol CarbonHotkeyRegistrarProtocol: AnyObject {
    func register(
        keyCode: UInt32, modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) -> HotkeyRegistrationToken?
    func cancel(_ token: HotkeyRegistrationToken)
}

public final class RealCarbonHotkeyRegistrar: CarbonHotkeyRegistrarProtocol {
    private struct Entry {
        let hotKeyRef: EventHotKeyRef
        let eventHandlerRef: EventHandlerRef
        let callbackBox: Unmanaged<EntryBox>
    }

    private var entries: [UInt64: Entry] = [:]
    private static let nextIDLock = OSAllocatedUnfairLock(initialState: UInt64(1))

    public init() {}

    deinit {
        for id in entries.keys { cancel(HotkeyRegistrationToken(id: id)) }
    }

    public func register(
        keyCode: UInt32, modifiers: UInt32,
        handler: @escaping @Sendable () -> Void
    ) -> HotkeyRegistrationToken? {
        let rawID = Self.nextIDLock.withLock { id -> UInt64 in
            let current = id; id = current == .max ? 1 : current + 1; return current
        }
        let token = HotkeyRegistrationToken(id: rawID)

        let hotKeyID = EventHotKeyID(signature: 0x4A534543, id: UInt32(truncatingIfNeeded: rawID))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let box = EntryBox(handler: handler, hotKeyID: UInt32(truncatingIfNeeded: rawID))
        let ptr = Unmanaged.passRetained(box).toOpaque()
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), entryCallback, 1, &eventType, ptr, &handlerRef)
        guard installStatus == noErr, let handlerRef else {
            UnregisterEventHotKey(ref)
            Unmanaged<EntryBox>.fromOpaque(ptr).release()
            return nil
        }

        entries[rawID] = Entry(hotKeyRef: ref, eventHandlerRef: handlerRef, callbackBox: Unmanaged<EntryBox>.fromOpaque(ptr))
        return token
    }

    public func cancel(_ token: HotkeyRegistrationToken) {
        guard let entry = entries.removeValue(forKey: token.id) else { return }
        RemoveEventHandler(entry.eventHandlerRef)
        UnregisterEventHotKey(entry.hotKeyRef)
        entry.callbackBox.release()
    }
}

private final class EntryBox {
    let handler: @Sendable () -> Void
    let hotKeyID: UInt32
    init(handler: @escaping @Sendable () -> Void, hotKeyID: UInt32) {
        self.handler = handler; self.hotKeyID = hotKeyID
    }
}

private let entryCallback: EventHandlerProcPtr = { _, event, userData in
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    let box = Unmanaged<EntryBox>.fromOpaque(userData).takeUnretainedValue()
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard err == noErr, hotKeyID.id == box.hotKeyID else { return OSStatus(eventNotHandledErr) }
    box.handler()
    return noErr
}
