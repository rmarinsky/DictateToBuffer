import Foundation
import AVFoundation
import Combine

final class AudioRecorderService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    // MARK: - Public Methods

    func startRecording(device: AudioDevice?, quality: AudioQuality) async throws {
        NSLog("[AudioRecorder] startRecording: BEGIN, isRecording=\(isRecording)")
        guard !isRecording else {
            NSLog("[AudioRecorder] startRecording: Already recording, returning")
            return
        }

        // Request microphone permission
        var permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioRecorder] startRecording: Permission status = \(permissionStatus.rawValue)")

        if permissionStatus == .notDetermined {
            NSLog("[AudioRecorder] startRecording: Requesting permission")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            NSLog("[AudioRecorder] startRecording: Permission request result = \(granted)")
            permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }

        guard permissionStatus == .authorized else {
            NSLog("[AudioRecorder] startRecording: Permission denied")
            throw AudioError.permissionDenied
        }

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictate_\(UUID().uuidString).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)
        NSLog("[AudioRecorder] startRecording: Recording URL = \(recordingURL?.path ?? "nil")")

        guard let url = recordingURL else {
            NSLog("[AudioRecorder] startRecording: Failed to create URL")
            throw AudioError.recordingFailed("Could not create recording file")
        }

        // Configure audio settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: quality.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        NSLog("[AudioRecorder] startRecording: Audio settings configured, sampleRate=\(quality.sampleRate)")

        // Set input device if specified
        if let device = device {
            NSLog("[AudioRecorder] startRecording: Setting input device: \(device.name)")
            setInputDevice(device.id)
        }

        // Create and start recorder
        NSLog("[AudioRecorder] startRecording: Creating AVAudioRecorder")
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()

        NSLog("[AudioRecorder] startRecording: Calling record()")
        guard audioRecorder?.record() == true else {
            NSLog("[AudioRecorder] startRecording: record() returned false")
            throw AudioError.recordingFailed("Failed to start recording")
        }

        isRecording = true
        startLevelMonitoring()
        NSLog("[AudioRecorder] startRecording: END, isRecording=\(isRecording)")
    }

    func stopRecording() async throws -> Data {
        NSLog("[AudioRecorder] stopRecording: BEGIN, isRecording=\(isRecording)")
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            NSLog("[AudioRecorder] stopRecording: No active recording! isRecording=\(isRecording), recorder=\(audioRecorder != nil), url=\(recordingURL?.path ?? "nil")")
            throw AudioError.recordingFailed("No active recording")
        }

        NSLog("[AudioRecorder] stopRecording: Stopping level monitoring")
        stopLevelMonitoring()
        NSLog("[AudioRecorder] stopRecording: Stopping recorder")
        recorder.stop()
        isRecording = false

        // Read audio data
        NSLog("[AudioRecorder] stopRecording: Reading audio data from \(url.path)")
        let audioData = try Data(contentsOf: url)
        NSLog("[AudioRecorder] stopRecording: Read \(audioData.count) bytes")

        // Cleanup
        try? FileManager.default.removeItem(at: url)
        audioRecorder = nil
        recordingURL = nil

        NSLog("[AudioRecorder] stopRecording: END")
        return audioData
    }

    func cancelRecording() {
        stopLevelMonitoring()
        audioRecorder?.stop()
        audioRecorder = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        isRecording = false
    }

    // MARK: - Private Methods

    private func setInputDevice(_ deviceID: AudioDeviceID) {
        // Set the default input device using CoreAudio
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    private func updateAudioLevel() {
        audioRecorder?.updateMeters()
        let level = audioRecorder?.averagePower(forChannel: 0) ?? -160

        // Convert dB to linear scale (0-1)
        let minDb: Float = -60
        let normalizedLevel = max(0, (level - minDb) / -minDb)
        audioLevel = normalizedLevel
    }
}
