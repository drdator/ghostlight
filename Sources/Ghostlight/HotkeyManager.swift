import Carbon

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false
    private let hotkeyID: UInt32

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        hotkeyID = Self.nextID
        Self.nextID += 1
        Self.handlers[hotkeyID] = handler
        Self.installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x474C4854), // "GLHT"
            id: hotkeyID
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            fputs("ghostlight: failed to register hotkey (\(status))\n", stderr)
        }
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                HotkeyManager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        eventHandlerInstalled = true
    }

    deinit {
        Self.handlers.removeValue(forKey: hotkeyID)
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
