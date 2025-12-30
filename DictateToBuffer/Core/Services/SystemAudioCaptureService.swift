import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@available(macOS 13.0, *)
final class SystemAudioCaptureService: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var isCapturing = false

    var includeMicrophone: Bool = false
    var onError: ((Error) -> Void)?
    var onCaptureStarted: (() -> Void)?

    // MARK: - Permission Check

    static func checkPermission() async -> Bool {
        do {
            // This will prompt for permission if not granted
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return !content.displays.isEmpty
        } catch {
            NSLog("[SystemAudio] Permission check failed: \(error)")
            return false
        }
    }

    static func requestPermission() async -> Bool {
        // Requesting shareable content triggers the permission dialog
        return await checkPermission()
    }

    // MARK: - Start Capture

    func startCapture(to outputURL: URL) async throws {
        guard !isCapturing else {
            NSLog("[SystemAudio] Already capturing")
            return
        }

        self.outputURL = outputURL

        NSLog("[SystemAudio] Starting system audio capture...")

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayFound
        }

        // Create filter for audio only (capture display but we only want audio)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream for audio capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // Minimal video
        config.showsCursor = false
        config.sampleRate = 48000
        config.channelCount = 2

        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)

        guard let stream = stream else {
            throw SystemAudioError.streamCreationFailed
        }

        // Add audio output
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dictate.buffer.systemaudio"))

        // Setup audio file for recording
        try setupAudioFile(at: outputURL)

        // Start capture
        try await stream.startCapture()
        isCapturing = true

        NSLog("[SystemAudio] Capture started successfully")
        onCaptureStarted?()
    }

    // MARK: - Stop Capture

    func stopCapture() async throws -> URL? {
        guard isCapturing, let stream = stream else {
            NSLog("[SystemAudio] Not capturing")
            return nil
        }

        NSLog("[SystemAudio] Stopping capture...")

        try await stream.stopCapture()
        self.stream = nil
        isCapturing = false

        // Close audio file
        audioFile = nil

        NSLog("[SystemAudio] Capture stopped, file saved to: \(outputURL?.path ?? "nil")")

        return outputURL
    }

    // MARK: - Audio File Setup

    private func setupAudioFile(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let format = AVAudioFormat(settings: settings)!
        audioFile = try AVAudioFile(forWriting: url, settings: settings)

        NSLog("[SystemAudio] Audio file created at: \(url.path)")
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[SystemAudio] Stream stopped with error: \(error)")
        isCapturing = false
        onError?(error)
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SystemAudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let audioFile = audioFile else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer and write to file
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }

        let format = AVAudioFormat(streamDescription: asbd)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        if let channelData = pcmBuffer.int16ChannelData {
            memcpy(channelData[0], data, length)
        }

        do {
            try audioFile.write(from: pcmBuffer)
        } catch {
            NSLog("[SystemAudio] Error writing audio: \(error)")
        }
    }
}

// MARK: - Errors

enum SystemAudioError: LocalizedError {
    case noDisplayFound
    case streamCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for screen capture"
        case .streamCreationFailed:
            return "Failed to create audio capture stream"
        case .permissionDenied:
            return "Screen recording permission required"
        }
    }
}
