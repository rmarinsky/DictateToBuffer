import AppKit
import Carbon
import Foundation

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        // Order: Control, Option, Shift, Command (standard macOS order)
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        if let char = keyCodeToString(keyCode) {
            parts.append(char.uppercased())
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H",
            5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
            21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            50: "`",
            // Special keys
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13",
            107: "F14", 109: "F10", 111: "F12", 113: "F15",
            118: "F4", 119: "F2", 120: "F1", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode]
    }

    /// Create from NSEvent
    static func from(event: NSEvent) -> KeyCombo? {
        let keyCode = UInt32(event.keyCode)
        var carbonModifiers: UInt32 = 0

        let flags = event.modifierFlags
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        // Require at least one modifier
        guard carbonModifiers != 0 else { return nil }

        return KeyCombo(keyCode: keyCode, modifiers: carbonModifiers)
    }

    /// Default hotkey: Cmd + Shift + D
    static let `default` = KeyCombo(
        keyCode: 2, // 'd' key
        modifiers: UInt32(cmdKey | shiftKey)
    )
}
