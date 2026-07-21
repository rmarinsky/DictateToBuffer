import Foundation

/// Builds a multipart request body on disk so multi-hour audio uploads do not
/// require a second full-size in-memory copy.
struct MultipartFormDataFile {
    let fileURL: URL
    let boundary: String
    let contentLength: UInt64

    static func create(
        audioURL: URL,
        filename: String,
        contentType: String,
        config: [String: Any],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> MultipartFormDataFile {
        let boundary = UUID().uuidString
        let bodyURL = temporaryDirectory
            .appendingPathComponent("diduny-upload-\(UUID().uuidString)")
            .appendingPathExtension("multipart")
        let fileManager = FileManager.default

        guard fileManager.createFile(atPath: bodyURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }

            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(
                contentsOf: Data(
                    "Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".utf8
                )
            )
            try output.write(contentsOf: Data("Content-Type: \(contentType)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: audioURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }

            let configData = try JSONSerialization.data(withJSONObject: config)
            try output.write(contentsOf: Data("\r\n--\(boundary)\r\n".utf8))
            try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"config\"\r\n".utf8))
            try output.write(contentsOf: Data("Content-Type: text/plain\r\n\r\n".utf8))
            try output.write(contentsOf: configData)
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))

            let size = try output.offset()
            return MultipartFormDataFile(fileURL: bodyURL, boundary: boundary, contentLength: size)
        } catch {
            try? fileManager.removeItem(at: bodyURL)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
