import Carbon

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                HotkeyManager.handler?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        var hotKeyID = EventHotKeyID(
            signature: OSType(0x474C4854), // "GLHT"
            id: 1
        )

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
