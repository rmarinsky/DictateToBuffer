import AVFoundation
@testable import Diduny
import XCTest

final class ImportedMediaAudioPreparerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedMediaAudioPreparerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func test_validate_acceptsMaximumSupportedDuration() {
        XCTAssertNoThrow(
            try ImportedMediaAudioPreparer.validate(
                durationSeconds: ImportedMediaAudioPreparer.maximumDurationSeconds
            )
        )
    }

    func test_validate_rejectsDurationAboveLimit() {
        XCTAssertThrowsError(
            try ImportedMediaAudioPreparer.validate(
                durationSeconds: ImportedMediaAudioPreparer.maximumDurationSeconds + 0.1
            )
        ) { error in
            XCTAssertEqual(
                error as? ImportedMediaAudioPreparer.PreparationError,
                .durationLimitExceeded(maximumMinutes: 300)
            )
        }
    }

    func test_validate_rejectsInvalidDurations() {
        for duration in [0, -1, .infinity, .nan] {
            XCTAssertThrowsError(
                try ImportedMediaAudioPreparer.validate(durationSeconds: duration)
            ) { error in
                XCTAssertEqual(
                    error as? ImportedMediaAudioPreparer.PreparationError,
                    .invalidDuration
                )
            }
        }
    }

    func test_prepare_writesCompactAudioOnlyM4A() async throws {
        let sourceURL = try makeWAV(durationSeconds: 1)
        let preparer = ImportedMediaAudioPreparer(temporaryDirectory: temporaryDirectory)

        let prepared = try await preparer.prepare(sourceURL: sourceURL)

        XCTAssertEqual(prepared.fileURL.pathExtension, "m4a")
        XCTAssertEqual(prepared.durationSeconds, 1, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let asset = AVURLAsset(url: prepared.fileURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertTrue(videoTracks.isEmpty)

        let outputSize = try prepared.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        XCTAssertGreaterThan(outputSize ?? 0, 0)
        XCTAssertLessThan(outputSize ?? .max, 20000)

        prepared.removeTemporaryFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.fileURL.path))
    }

    func test_prepare_videoFixture_extractsAudioOnly() async throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["DIDUNY_TEST_VIDEO_FILE"],
              !fixturePath.isEmpty
        else {
            throw XCTSkip("Set DIDUNY_TEST_VIDEO_FILE to run the video-container integration test.")
        }

        let sourceURL = URL(fileURLWithPath: fixturePath)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceVideoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        let sourceAudioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(sourceVideoTracks.isEmpty)
        XCTAssertFalse(sourceAudioTracks.isEmpty)

        let prepared = try await ImportedMediaAudioPreparer(
            temporaryDirectory: temporaryDirectory
        ).prepare(sourceURL: sourceURL)
        defer { prepared.removeTemporaryFile() }

        let preparedAsset = AVURLAsset(url: prepared.fileURL)
        let preparedAudioTracks = try await preparedAsset.loadTracks(withMediaType: .audio)
        let preparedVideoTracks = try await preparedAsset.loadTracks(withMediaType: .video)
        XCTAssertFalse(preparedAudioTracks.isEmpty)
        XCTAssertTrue(preparedVideoTracks.isEmpty)
    }

    private func makeWAV(durationSeconds: TimeInterval) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("source.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(durationSeconds * 44100)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frameCount

        for channel in 0 ..< Int(buffer.format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0 ..< Int(frameCount) {
                samples[frame] = 0.1 * sin(Float(frame) * 2 * .pi * 440 / 44100)
            }
        }
        try file.write(from: buffer)
        return url
    }
}
