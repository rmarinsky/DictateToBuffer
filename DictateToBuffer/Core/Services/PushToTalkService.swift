import Foundation
import AppKit
import Carbon

final class PushToTalkService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isKeyPressed = false
    private var isReady = false
    private var startTime: Date?

    var selectedKey: PushToTalkKey = .none
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func start() {
        stop()

        guard selectedKey != .none else { return }

        // Mark not ready initially - ignore events for first 0.5 seconds
        isReady = false
        startTime = Date()

        // Monitor flags changed events globally
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor locally when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Become ready after cooldown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isReady = true
            NSLog("[PushToTalk] Now ready to accept input")
        }

        NSLog("[PushToTalk] Started monitoring for \(selectedKey.displayName)")
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isKeyPressed = false
        isReady = false
        startTime = nil
        NSLog("[PushToTalk] Stopped monitoring")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Ignore events during cooldown period
        guard isReady else { return }

        let flags = event.modifierFlags
        let keyCode = event.keyCode

        let isPressed: Bool

        switch selectedKey {
        case .none:
            return

        case .capsLock:
            // Caps Lock toggles, so we check if it was just pressed
            // keyCode 57 is Caps Lock
            isPressed = keyCode == 57 && flags.contains(.capsLock)

        case .rightShift:
            // Right Shift has keyCode 60
            isPressed = keyCode == 60 && flags.contains(.shift)

        case .rightOption:
            // Right Option has keyCode 61
            isPressed = keyCode == 61 && flags.contains(.option)
        }

        // For Caps Lock, we need special handling since it's a toggle key
        if selectedKey == .capsLock {
            if keyCode == 57 {
                if !isKeyPressed {
                    isKeyPressed = true
                    NSLog("[PushToTalk] Caps Lock pressed - starting recording")
                    onKeyDown?()
                } else {
                    isKeyPressed = false
                    NSLog("[PushToTalk] Caps Lock released - stopping recording")
                    onKeyUp?()
                }
            }
        } else {
            // For Right Shift and Right Option
            if isPressed && !isKeyPressed {
                isKeyPressed = true
                NSLog("[PushToTalk] \(selectedKey.displayName) pressed - starting recording")
                onKeyDown?()
            } else if !isPressed && isKeyPressed && isCorrectKeyCode(keyCode) {
                isKeyPressed = false
                NSLog("[PushToTalk] \(selectedKey.displayName) released - stopping recording")
                onKeyUp?()
            }
        }
    }

    private func isCorrectKeyCode(_ keyCode: UInt16) -> Bool {
        switch selectedKey {
        case .none:
            return false
        case .capsLock:
            return keyCode == 57
        case .rightShift:
            return keyCode == 60
        case .rightOption:
            return keyCode == 61
        }
    }
}
