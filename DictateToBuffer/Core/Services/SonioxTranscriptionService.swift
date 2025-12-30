import Foundation

final class SonioxTranscriptionService {
    var apiKey: String?

    private let baseURL = "https://api.soniox.com/v1"
    private let defaultModel = "stt-async-preview"
    private let pollingInterval: TimeInterval = 1.0
    private let maxPollingAttempts = 60 // 60 seconds max wait

    func transcribe(audioData: Data, language: String? = nil) async throws -> String {
        NSLog("[Transcription] transcribe: BEGIN, audioData size = \(audioData.count) bytes")

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            NSLog("[Transcription] transcribe: No API key!")
            throw TranscriptionError.noAPIKey
        }

        // Step 1: Upload the audio file
        NSLog("[Transcription] Step 1: Uploading audio file...")
        let fileId = try await uploadFile(audioData: audioData, apiKey: apiKey)
        NSLog("[Transcription] File uploaded, fileId = \(fileId)")

        // Step 2: Create transcription job
        NSLog("[Transcription] Step 2: Creating transcription job...")
        let transcriptionId = try await createTranscription(fileId: fileId, language: language, apiKey: apiKey)
        NSLog("[Transcription] Transcription created, id = \(transcriptionId)")

        // Step 3: Poll for completion
        NSLog("[Transcription] Step 3: Polling for completion...")
        try await waitForCompletion(transcriptionId: transcriptionId, apiKey: apiKey)
        NSLog("[Transcription] Transcription completed")

        // Step 4: Get the transcript text
        NSLog("[Transcription] Step 4: Retrieving transcript...")
        let text = try await getTranscript(transcriptionId: transcriptionId, apiKey: apiKey)
        NSLog("[Transcription] Transcript retrieved: \(text.prefix(50))...")

        return text
    }

    // MARK: - Step 1: Upload File

    private func uploadFile(audioData: Data, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/files")!

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        NSLog("[Transcription] uploadFile: HTTP status = \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("[Transcription] uploadFile: Error - \(errorBody)")
            throw TranscriptionError.apiError("Upload failed: \(errorBody)")
        }

        let uploadResponse = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        return uploadResponse.id
    }

    // MARK: - Step 2: Create Transcription

    private func createTranscription(fileId: String, language: String?, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "file_id": fileId,
            "model": defaultModel
        ]

        if let lang = language {
            payload["language_hints"] = [lang]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        NSLog("[Transcription] createTranscription: HTTP status = \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("[Transcription] createTranscription: Error - \(errorBody)")
            throw TranscriptionError.apiError("Create transcription failed: \(errorBody)")
        }

        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.id
    }

    // MARK: - Step 3: Poll for Completion

    private func waitForCompletion(transcriptionId: String, apiKey: String) async throws {
        let url = URL(string: "\(baseURL)/transcriptions/\(transcriptionId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for attempt in 1...maxPollingAttempts {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("[Transcription] Poll error: \(errorBody)")
                throw TranscriptionError.invalidResponse
            }

            let statusResponse = try JSONDecoder().decode(TranscriptionStatusResponse.self, from: data)
            NSLog("[Transcription] Poll attempt \(attempt): status = \(statusResponse.status)")

            switch statusResponse.status {
            case "completed":
                return
            case "error":
                let errorMsg = statusResponse.error_message ?? "Unknown error"
                let errorType = statusResponse.error_type ?? "unknown"
                NSLog("[Transcription] Transcription failed: \(errorType) - \(errorMsg)")
                throw TranscriptionError.apiError("Transcription failed: \(errorMsg)")
            case "queued", "processing":
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            default:
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }

        throw TranscriptionError.apiError("Transcription timed out after \(maxPollingAttempts) seconds")
    }

    // MARK: - Step 4: Get Transcript

    private func getTranscript(transcriptionId: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/transcriptions/\(transcriptionId)/transcript")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        NSLog("[Transcription] getTranscript: HTTP status = \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("[Transcription] getTranscript: Error - \(errorBody)")
            throw TranscriptionError.apiError("Get transcript failed: \(errorBody)")
        }

        let transcriptResponse = try JSONDecoder().decode(TranscriptResponse.self, from: data)

        guard !transcriptResponse.text.isEmpty else {
            throw TranscriptionError.emptyTranscription
        }

        return transcriptResponse.text
    }

    // MARK: - Test Connection

    func testConnection() async throws -> Bool {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        // Use the models endpoint to verify API key works
        let url = URL(string: "\(baseURL)/models")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        // 200 = success, 401/403 = bad API key
        if httpResponse.statusCode == 200 {
            return true
        } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Invalid API key"
            throw TranscriptionError.apiError(errorBody)
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError("Status \(httpResponse.statusCode): \(errorBody)")
        }
    }
}

// MARK: - Response Models

private struct FileUploadResponse: Decodable {
    let id: String
    let filename: String
    let size: Int
    let created_at: String
    let client_reference_id: String?
}

private struct TranscriptionResponse: Decodable {
    let id: String
    let status: String
    let model: String
    let filename: String
    let error_message: String?
}

private struct TranscriptionStatusResponse: Decodable {
    let id: String
    let status: String
    let error_message: String?
    let error_type: String?
}

private struct TranscriptResponse: Decodable {
    let id: String
    let text: String
    let tokens: [TranscriptToken]
}

private struct TranscriptToken: Decodable {
    let text: String
    let start_ms: Int
    let end_ms: Int
    let confidence: Double
    let speaker: String?
    let language: String?
}
