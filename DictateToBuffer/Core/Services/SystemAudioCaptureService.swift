import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os

@available(macOS 13.0, *)
final class SystemAudioCaptureService: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var isCapturing = false
    private var outputFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    private var sampleCount: Int = 0

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
            Log.audio.info("Permission check failed: \(error)")
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
            Log.audio.info("Already capturing")
            return
        }

        self.outputURL = outputURL

        Log.audio.info("Starting system audio capture...")

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

        Log.audio.info("Capture started successfully")
        onCaptureStarted?()
    }

    // MARK: - Stop Capture

    func stopCapture() async throws -> URL? {
        guard isCapturing, let stream = stream else {
            Log.audio.info("Not capturing")
            return nil
        }

        Log.audio.info("Stopping capture... Total samples processed: \(self.sampleCount)")

        try await stream.stopCapture()
        self.stream = nil
        isCapturing = false

        // Close audio file and cleanup
        audioFile = nil
        audioConverter = nil
        outputFormat = nil
        sampleCount = 0

        Log.audio.info("Capture stopped, file saved to: \(self.outputURL?.path ?? "nil")")

        return outputURL
    }

    // MARK: - Audio File Setup

    private func setupAudioFile(at url: URL) throws {
        // Use 32-bit float format to match ScreenCaptureKit output
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Create output format for conversion
        outputFormat = AVAudioFormat(settings: settings)

        audioFile = try AVAudioFile(forWriting: url, settings: settings)

        Log.audio.info("Audio file created at: \(url.path)")
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.audio.info("Stream stopped with error: \(error)")
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

        // Get format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        // Log first few samples for debugging
        sampleCount += 1
        if sampleCount <= 3 {
            let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            Log.audio.info("Audio sample \(self.sampleCount): frames=\(numSamples), sampleRate=\(asbd.pointee.mSampleRate), channels=\(asbd.pointee.mChannelsPerFrame), bitsPerChannel=\(asbd.pointee.mBitsPerChannel), isFloat=\(isFloat), isNonInterleaved=\(isNonInterleaved)")
        }

        // Create AVAudioFormat from the stream description
        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else {
            Log.audio.info("Failed to create input format")
            return
        }

        // Create PCM buffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(numSamples)) else {
            Log.audio.info("Failed to create PCM buffer")
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Get audio data from sample buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            Log.audio.info("Failed to get data buffer")
            return
        }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            Log.audio.info("Failed to get data pointer, status: \(status)")
            return
        }

        // Copy data to PCM buffer based on format
        let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        if isNonInterleaved {
            // Non-interleaved: each channel's data is contiguous
            let channelCount = Int(asbd.pointee.mChannelsPerFrame)
            let bytesPerFrame = Int(asbd.pointee.mBytesPerFrame)
            let framesPerBuffer = numSamples

            if let floatChannelData = pcmBuffer.floatChannelData {
                for channel in 0..<channelCount {
                    let channelOffset = channel * framesPerBuffer * bytesPerFrame
                    let srcPtr = data.advanced(by: channelOffset)
                    let dstPtr = floatChannelData[channel]
                    memcpy(dstPtr, srcPtr, framesPerBuffer * bytesPerFrame)
                }
            }
        } else {
            // Interleaved: samples are interleaved
            if let floatChannelData = pcmBuffer.floatChannelData {
                // For interleaved stereo float, data is [L0, R0, L1, R1, ...]
                let srcPtr = UnsafeRawPointer(data)
                let channelCount = Int(asbd.pointee.mChannelsPerFrame)
                let bytesPerSample = Int(asbd.pointee.mBitsPerChannel / 8)

                for frame in 0..<numSamples {
                    for channel in 0..<channelCount {
                        let srcOffset = (frame * channelCount + channel) * bytesPerSample
                        let value = srcPtr.load(fromByteOffset: srcOffset, as: Float.self)
                        floatChannelData[channel][frame] = value
                    }
                }
            }
        }

        // Write to file - may need format conversion
        do {
            let fileFormat = audioFile.processingFormat

            if inputFormat == fileFormat {
                try audioFile.write(from: pcmBuffer)
            } else {
                // Need format conversion
                if audioConverter == nil {
                    audioConverter = AVAudioConverter(from: inputFormat, to: fileFormat)
                }

                guard let converter = audioConverter else {
                    Log.audio.info("Failed to create converter")
                    return
                }

                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(numSamples)) else {
                    Log.audio.info("Failed to create output buffer")
                    return
                }

                var error: NSError?
                var hasData = true
                converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return pcmBuffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }

                if let error = error {
                    Log.audio.info("Conversion error: \(error)")
                    return
                }

                if outputBuffer.frameLength > 0 {
                    try audioFile.write(from: outputBuffer)
                }
            }
        } catch {
            Log.audio.info("Error writing audio: \(error)")
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
