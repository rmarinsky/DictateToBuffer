import Foundation
import AVFoundation
import Combine
import os

@MainActor
final class AudioRecorderService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelTimer: Timer?

    // MARK: - Public Methods

    func startRecording(device: AudioDevice?, quality: AudioQuality) async throws {
        Log.audio.info("startRecording: BEGIN, isRecording=\(self.isRecording)")
        guard !isRecording else {
            Log.audio.info("startRecording: Already recording, returning")
            return
        }

        // Request microphone permission
        var permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.audio.info("startRecording: Permission status = \(permissionStatus.rawValue)")

        if permissionStatus == .notDetermined {
            Log.audio.info("startRecording: Requesting permission")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Log.audio.info("startRecording: Permission request result = \(granted)")
            permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }

        guard permissionStatus == .authorized else {
            Log.audio.info("startRecording: Permission denied")
            throw AudioError.permissionDenied
        }

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictate_\(UUID().uuidString).wav"
        recordingURL = tempDir.appendingPathComponent(fileName)
        Log.audio.info("startRecording: Recording URL = \(self.recordingURL?.path ?? "nil")")

        guard let url = recordingURL else {
            Log.audio.info("startRecording: Failed to create URL")
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
        Log.audio.info("startRecording: Audio settings configured, sampleRate=\(quality.sampleRate)")

        // Set input device if specified
        if let device = device {
            Log.audio.info("startRecording: Setting input device: \(device.name)")
            setInputDevice(device.id)
        }

        // Create and start recorder
        Log.audio.info("startRecording: Creating AVAudioRecorder")
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()

        Log.audio.info("startRecording: Calling record()")
        guard audioRecorder?.record() == true else {
            Log.audio.info("startRecording: record() returned false")
            throw AudioError.recordingFailed("Failed to start recording")
        }

        isRecording = true
        startLevelMonitoring()
        Log.audio.info("startRecording: END, isRecording=\(self.isRecording)")
    }

    func stopRecording() async throws -> Data {
        Log.audio.info("stopRecording: BEGIN, isRecording=\(self.isRecording)")
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            Log.audio.info("stopRecording: No active recording! isRecording=\(self.isRecording), recorder=\(self.audioRecorder != nil), url=\(self.recordingURL?.path ?? "nil")")
            throw AudioError.recordingFailed("No active recording")
        }

        Log.audio.info("stopRecording: Stopping level monitoring")
        stopLevelMonitoring()
        Log.audio.info("stopRecording: Stopping recorder")
        recorder.stop()
        isRecording = false

        // Read audio data
        Log.audio.info("stopRecording: Reading audio data from \(url.path)")
        let audioData = try Data(contentsOf: url)
        Log.audio.info("stopRecording: Read \(audioData.count) bytes")

        // Cleanup
        try? FileManager.default.removeItem(at: url)
        audioRecorder = nil
        recordingURL = nil

        Log.audio.info("stopRecording: END")
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
            Task { @MainActor in
                self?.updateAudioLevel()
            }
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
