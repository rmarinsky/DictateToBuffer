@testable import Diduny
import Foundation
import XCTest

final class MultipartFormDataFileTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultipartFormDataFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func test_create_streamsAudioAndConfigIntoDiskBackedMultipartBody() throws {
        let audioURL = temporaryDirectory.appendingPathComponent("audio.m4a")
        let audioMarker = Data("unique-audio-payload".utf8)
        try audioMarker.write(to: audioURL)

        let multipart = try MultipartFormDataFile.create(
            audioURL: audioURL,
            filename: "recording.m4a",
            contentType: "audio/mp4",
            config: ["mode": "transcribe", "language_hints": ["uk"]],
            temporaryDirectory: temporaryDirectory
        )

        let body = try Data(contentsOf: multipart.fileURL)
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        XCTAssertEqual(multipart.contentLength, UInt64(body.count))
        XCTAssertTrue(bodyText.contains("name=\"audio\"; filename=\"recording.m4a\""))
        XCTAssertTrue(bodyText.contains("Content-Type: audio/mp4"))
        XCTAssertTrue(body.range(of: audioMarker) != nil)
        XCTAssertTrue(bodyText.contains("\"mode\":\"transcribe\""))
        XCTAssertTrue(bodyText.contains("--\(multipart.boundary)--"))

        multipart.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: multipart.fileURL.path))
    }
}
