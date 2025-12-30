import Foundation
import AppKit
import AVFoundation
import UserNotifications
import ApplicationServices

/// Manages all permission requests for the app
final class PermissionManager {
    static let shared = PermissionManager()
    
    // MARK: - Permission Status
    
    struct PermissionStatus {
        var microphone: Bool = false
        var screenRecording: Bool = false
        var accessibility: Bool = false
        var notifications: Bool = false
        
        var allGranted: Bool {
            microphone && accessibility && notifications
        }
        
        var allCriticalGranted: Bool {
            microphone && accessibility
        }
    }
    
    private(set) var status = PermissionStatus()
    
    // Callback for when all permissions are checked/granted
    var onPermissionsReady: ((PermissionStatus) -> Void)?
    
    private init() {}
    
    // MARK: - Request All Permissions
    
    /// Request all permissions at app launch
    func requestAllPermissions(completion: @escaping (PermissionStatus) -> Void) {
        NSLog("[PermissionManager] Starting permission requests...")
        
        // Create a group to track all async requests
        let group = DispatchGroup()
        
        // 1. Request microphone permission (required)
        group.enter()
        requestMicrophonePermission { granted in
            self.status.microphone = granted
            NSLog("[PermissionManager] Microphone: \(granted)")
            group.leave()
        }
        
        // 2. Request notification permission (nice to have)
        group.enter()
        requestNotificationPermission { granted in
            self.status.notifications = granted
            NSLog("[PermissionManager] Notifications: \(granted)")
            group.leave()
        }
        
        // 3. Check accessibility permission (required for auto-paste)
        status.accessibility = checkAccessibilityPermission()
        NSLog("[PermissionManager] Accessibility: \(status.accessibility)")
        
        // 4. Check screen recording permission (required for meeting recording)
        Task {
            group.enter()
            let granted = await checkScreenRecordingPermission()
            self.status.screenRecording = granted
            NSLog("[PermissionManager] Screen Recording: \(granted)")
            group.leave()
        }
        
        // Wait for all permission checks to complete
        group.notify(queue: .main) {
            NSLog("[PermissionManager] All permissions checked")
            NSLog("[PermissionManager] Status: Mic=\(self.status.microphone), Screen=\(self.status.screenRecording), Accessibility=\(self.status.accessibility), Notifications=\(self.status.notifications)")
            
            // Show permission prompt if needed
            if !self.status.allCriticalGranted {
                self.showPermissionPrompt(completion: completion)
            } else {
                completion(self.status)
                self.onPermissionsReady?(self.status)
            }
        }
    }
    
    // MARK: - Individual Permission Requests
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
            
        case .denied, .restricted:
            completion(false)
            
        @unknown default:
            completion(false)
        }
    }
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    @available(macOS 13.0, *)
    func checkScreenRecordingPermission() async -> Bool {
        return await SystemAudioCaptureService.checkPermission()
    }
    
    // MARK: - Permission Prompt UI
    
    private func showPermissionPrompt(completion: @escaping (PermissionStatus) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "DictateToBuffer Needs Permissions"
            alert.alertStyle = .informational
            
            var message = "To function properly, DictateToBuffer needs the following permissions:\n\n"
            
            if !self.status.microphone {
                message += "🎤 Microphone Access (Required)\n   • Record audio for transcription\n\n"
            }
            
            if !self.status.accessibility {
                message += "♿️ Accessibility Access (Required)\n   • Auto-paste transcribed text\n\n"
            }
            
            if !self.status.screenRecording {
                message += "🖥️ Screen Recording (Optional)\n   • Record meeting audio\n\n"
            }
            
            if !self.status.notifications {
                message += "🔔 Notifications (Optional)\n   • Show transcription completion alerts\n\n"
            }
            
            message += "Click 'Grant Permissions' to open System Settings and enable these permissions."
            
            alert.informativeText = message
            alert.addButton(withTitle: "Grant Permissions")
            alert.addButton(withTitle: "Later")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                self.openSystemSettings(completion: completion)
            } else {
                completion(self.status)
                self.onPermissionsReady?(self.status)
            }
        }
    }
    
    private func openSystemSettings(completion: @escaping (PermissionStatus) -> Void) {
        // Determine which settings to open based on what's missing
        var urlString: String?
        
        if !status.microphone {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        } else if !status.accessibility {
            // Request accessibility with prompt
            requestAccessibilityPermission()
            
            // Recheck after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.recheckPermissions(completion: completion)
            }
            return
        } else if !status.screenRecording {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        
        if let urlString = urlString, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            
            // Recheck permissions after user has time to grant them
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.recheckPermissions(completion: completion)
            }
        } else {
            completion(self.status)
            self.onPermissionsReady?(self.status)
        }
    }
    
    private func recheckPermissions(completion: @escaping (PermissionStatus) -> Void) {
        NSLog("[PermissionManager] Rechecking permissions...")
        
        let group = DispatchGroup()
        
        // Recheck microphone
        group.enter()
        requestMicrophonePermission { granted in
            self.status.microphone = granted
            group.leave()
        }
        
        // Recheck accessibility
        status.accessibility = checkAccessibilityPermission()
        
        // Recheck screen recording
        if #available(macOS 13.0, *) {
            Task {
                group.enter()
                let granted = await checkScreenRecordingPermission()
                self.status.screenRecording = granted
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            NSLog("[PermissionManager] Recheck complete: Mic=\(self.status.microphone), Screen=\(self.status.screenRecording), Accessibility=\(self.status.accessibility)")
            
            // If still missing critical permissions, offer to try again
            if !self.status.allCriticalGranted {
                self.showPermissionFollowUp(completion: completion)
            } else {
                completion(self.status)
                self.onPermissionsReady?(self.status)
            }
        }
    }
    
    private func showPermissionFollowUp(completion: @escaping (PermissionStatus) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permissions Still Required"
            alert.informativeText = "DictateToBuffer still needs some permissions to function properly. You can continue without them, but some features may not work.\n\nYou can grant permissions later in Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Continue Anyway")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                self.openSystemSettings(completion: completion)
            } else {
                completion(self.status)
                self.onPermissionsReady?(self.status)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Refresh permission status
    func refreshStatus() {
        status.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        status.accessibility = checkAccessibilityPermission()
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.status.notifications = settings.authorizationStatus == .authorized
            }
        }
        
        if #available(macOS 13.0, *) {
            Task {
                status.screenRecording = await checkScreenRecordingPermission()
            }
        }
    }
    
    /// Show individual permission alert
    func showPermissionAlert(for type: PermissionType) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            
            switch type {
            case .microphone:
                alert.messageText = "Microphone Access Required"
                alert.informativeText = "DictateToBuffer needs microphone access to record audio for transcription.\n\nPlease enable it in System Settings > Privacy & Security > Microphone."
                
            case .accessibility:
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "To auto-paste transcribed text, DictateToBuffer needs accessibility permission.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
                
            case .screenRecording:
                alert.messageText = "Screen Recording Permission Required"
                alert.informativeText = "To record meeting audio, DictateToBuffer needs screen recording permission.\n\nPlease enable it in System Settings > Privacy & Security > Screen Recording."
                
            case .notifications:
                alert.messageText = "Notification Permission"
                alert.informativeText = "DictateToBuffer can show notifications when transcription is complete."
            }
            
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSystemSettingsForPermission(type)
            }
        }
    }
    
    private func openSystemSettingsForPermission(_ type: PermissionType) {
        var urlString: String?
        
        switch type {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            requestAccessibilityPermission()
            return
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications:
            // No direct URL for notifications
            urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        
        if let urlString = urlString, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Types

enum PermissionType {
    case microphone
    case accessibility
    case screenRecording
    case notifications
}
