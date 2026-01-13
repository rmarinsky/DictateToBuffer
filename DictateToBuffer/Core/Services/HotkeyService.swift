import Carbon
import Foundation

final class HotkeyService {
    private var hotkeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    private static var sharedInstance: HotkeyService?
    private var eventHandler: EventHandlerRef?

    func register(keyCombo: KeyCombo, handler: @escaping () -> Void) throws {
        // Store handler
        self.handler = handler
        HotkeyService.sharedInstance = self

        // Create hotkey ID
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x4454_4246) // "DTBF"
        hotkeyID.id = 1

        // Register hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                HotkeyService.sharedInstance?.handler?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            throw NSError(domain: "HotkeyService", code: Int(status), userInfo: nil)
        }

        let registerStatus = RegisterEventHotKey(
            keyCombo.keyCode,
            keyCombo.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard registerStatus == noErr else {
            throw NSError(domain: "HotkeyService", code: Int(registerStatus), userInfo: nil)
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }

        handler = nil
        HotkeyService.sharedInstance = nil
    }
}
