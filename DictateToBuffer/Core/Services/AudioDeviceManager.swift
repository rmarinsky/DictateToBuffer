import Foundation
import CoreAudio
import AVFoundation
import Combine

final class AudioDeviceManager: ObservableObject {
    @Published private(set) var availableDevices: [AudioDevice] = []
    @Published private(set) var defaultDevice: AudioDevice?

    private var deviceChangeObserver: Any?

    init() {
        refreshDevices()
        setupDeviceChangeListener()
    }

    deinit {
        if let observer = deviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    func refreshDevices() {
        availableDevices = getInputDevices()
        defaultDevice = availableDevices.first { $0.isDefault }
    }

    func autoDetectBestDevice() async -> AudioDevice? {
        let devices = availableDevices
        guard !devices.isEmpty else { return nil }

        // Sample all devices simultaneously
        let results = await withTaskGroup(of: (AudioDeviceID, Float).self) { group in
            for device in devices {
                group.addTask {
                    let level = await self.measureSignalLevel(deviceID: device.id)
                    return (device.id, level)
                }
            }

            var results: [AudioDeviceID: Float] = [:]
            for await (deviceID, level) in group {
                results[deviceID] = level
            }
            return results
        }

        // Find device with highest signal
        let bestDeviceID = results.max(by: { $0.value < $1.value })?.key
        return devices.first { $0.id == bestDeviceID }
    }

    // MARK: - Private Methods

    private func getInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return [] }

        let defaultInputID = getDefaultInputDeviceID()

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard let name = getDeviceName(deviceID),
                  let inputChannels = getInputChannelCount(deviceID),
                  inputChannels > 0 else {
                return nil
            }

            let sampleRate = getDeviceSampleRate(deviceID) ?? 44100

            return AudioDevice(
                id: deviceID,
                name: name,
                inputChannels: inputChannels,
                sampleRate: sampleRate,
                isDefault: deviceID == defaultInputID
            )
        }
    }

    private func getDefaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func getInputChannelCount(_ deviceID: AudioDeviceID) -> Int? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return nil }

        let bufferList = bufferListPointer.pointee
        var channelCount = 0

        for i in 0..<Int(bufferList.mNumberBuffers) {
            let buffer = withUnsafePointer(to: &bufferListPointer.pointee.mBuffers) {
                $0.advanced(by: i).pointee
            }
            channelCount += Int(buffer.mNumberChannels)
        }

        return channelCount
    }

    private func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &sampleRate)
        return status == noErr ? sampleRate : nil
    }

    private func measureSignalLevel(deviceID: AudioDeviceID, duration: TimeInterval = 1.0) async -> Float {
        await withCheckedContinuation { continuation in
            var rmsValue: Float = 0

            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode

            // Try to set the device
            // Note: Setting specific device requires additional CoreAudio calls

            let format = inputNode.outputFormat(forBus: 0)
            let sampleCount = Int(format.sampleRate * duration)

            var samples: [Float] = []
            samples.reserveCapacity(sampleCount)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)

                if let data = channelData {
                    for i in 0..<frameLength {
                        samples.append(data[i])
                    }
                }
            }

            do {
                try audioEngine.start()

                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    audioEngine.stop()
                    inputNode.removeTap(onBus: 0)

                    if !samples.isEmpty {
                        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
                        rmsValue = sqrt(sumOfSquares / Float(samples.count))
                    }

                    continuation.resume(returning: rmsValue)
                }
            } catch {
                continuation.resume(returning: 0)
            }
        }
    }

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
    }
}
