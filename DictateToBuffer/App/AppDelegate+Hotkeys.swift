import Foundation

// MARK: - Hotkey & Push to Talk

extension AppDelegate {
    func setupHotkey() {
        let settings = SettingsStorage.shared
        if let hotkey = settings.globalHotkey {
            try? hotkeyService.register(keyCombo: hotkey) { [weak self] in
                self?.toggleRecording()
            }
        }
    }

    func setupPushToTalk() {
        let key = SettingsStorage.shared.pushToTalkKey
        pushToTalkService.selectedKey = key

        pushToTalkService.onKeyDown = { [weak self] in
            guard let self else { return }
            Task {
                await self.startRecordingIfIdle()
            }
        }

        pushToTalkService.onKeyUp = { [weak self] in
            guard let self else { return }
            Task {
                await self.stopRecordingIfRecording()
            }
        }

        if key != .none {
            pushToTalkService.start()
        }
    }

    @objc func pushToTalkKeyChanged(_ notification: Notification) {
        guard let key = notification.object as? PushToTalkKey else { return }
        Log.app.info("Push-to-talk key changed to: \(key.displayName)")

        pushToTalkService.stop()
        pushToTalkService.selectedKey = key

        if key != .none {
            pushToTalkService.start()
        }
    }

    @objc func hotkeyChanged(_ notification: Notification) {
        Log.app.info("Hotkey changed")

        // Unregister old hotkey
        hotkeyService.unregister()

        // Register new hotkey if set
        if let combo = notification.object as? KeyCombo {
            Log.app.info("Registering new hotkey: \(combo.displayString)")
            try? hotkeyService.register(keyCombo: combo) { [weak self] in
                self?.toggleRecording()
            }
        }
    }

    // MARK: - Translation Hotkey

    func setupTranslationHotkey() {
        let settings = SettingsStorage.shared
        if let hotkey = settings.translationHotkey {
            try? translationHotkeyService.register(keyCombo: hotkey) { [weak self] in
                self?.toggleTranslationRecording()
            }
        }
    }

    @objc func translationHotkeyChanged(_ notification: Notification) {
        Log.app.info("Translation hotkey changed")

        // Unregister old hotkey
        translationHotkeyService.unregister()

        // Register new hotkey if set
        if let combo = notification.object as? KeyCombo {
            Log.app.info("Registering new translation hotkey: \(combo.displayString)")
            try? translationHotkeyService.register(keyCombo: combo) { [weak self] in
                self?.toggleTranslationRecording()
            }
        }
    }

    // MARK: - Translation Push to Talk

    func setupTranslationPushToTalk() {
        let key = SettingsStorage.shared.translationPushToTalkKey
        translationPushToTalkService.selectedKey = key

        translationPushToTalkService.onKeyDown = { [weak self] in
            guard let self else { return }
            Task {
                await self.startTranslationRecordingIfIdle()
            }
        }

        translationPushToTalkService.onKeyUp = { [weak self] in
            guard let self else { return }
            Task {
                await self.stopTranslationRecordingIfRecording()
            }
        }

        if key != .none {
            translationPushToTalkService.start()
        }
    }

    @objc func translationPushToTalkKeyChanged(_ notification: Notification) {
        guard let key = notification.object as? PushToTalkKey else { return }
        Log.app.info("Translation push-to-talk key changed to: \(key.displayName)")

        translationPushToTalkService.stop()
        translationPushToTalkService.selectedKey = key

        if key != .none {
            translationPushToTalkService.start()
        }
    }
}
