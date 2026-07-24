@testable import Diduny
import XCTest

final class YouTubeRemoteMediaSourceTests: XCTestCase {
    func test_normalize_acceptsWatchShareShortsAndParameterizedURLs() throws {
        let urls = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ?t=42",
            "https://youtube.com/shorts/dQw4w9WgXcQ?feature=share",
            "https://m.youtube.com/watch?list=PL123&v=dQw4w9WgXcQ"
        ]

        let sources = try urls.map(YouTubeRemoteMediaSource.normalize)

        XCTAssertEqual(Set(sources.map(\.mediaID)), ["dQw4w9WgXcQ"])
        XCTAssertEqual(
            Set(sources.map(\.canonicalURL.absoluteString)),
            ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"]
        )
    }

    func test_normalize_rejectsPlaylistOtherProviderAndMalformedVideoID() {
        XCTAssertThrowsError(try YouTubeRemoteMediaSource.normalize("https://youtube.com/playlist?list=PL123"))
        XCTAssertThrowsError(try YouTubeRemoteMediaSource.normalize("https://vimeo.com/123456"))
        XCTAssertThrowsError(try YouTubeRemoteMediaSource.normalize("https://youtu.be/not-valid"))
    }

    func test_normalizeBatch_removesRepeatedCanonicalVideoIDs() throws {
        let sources = try YouTubeRemoteMediaSource.normalizeBatch(
            """
            https://youtu.be/dQw4w9WgXcQ
            https://youtube.com/watch?v=dQw4w9WgXcQ&t=10
            https://youtube.com/shorts/aqz-KE-bpKQ
            """
        )

        XCTAssertEqual(sources.map(\.mediaID), ["dQw4w9WgXcQ", "aqz-KE-bpKQ"])
    }

    func test_captionSelection_prefersAuthoredOriginalLanguageThenAutomatic() {
        let authored = RemoteCaptionTrack(
            languageCode: "uk",
            displayName: "Ukrainian",
            kind: .authored
        )
        let automatic = RemoteCaptionTrack(
            languageCode: "uk-orig",
            displayName: "Ukrainian (auto-generated)",
            kind: .automatic
        )

        XCTAssertEqual(
            RemoteCaptionTrack.preferred(
                authored: [authored],
                automatic: [automatic],
                originalLanguageCode: "uk"
            ),
            authored
        )
        XCTAssertEqual(
            RemoteCaptionTrack.preferred(
                authored: [],
                automatic: [automatic],
                originalLanguageCode: "uk"
            ),
            automatic
        )
        XCTAssertNil(
            RemoteCaptionTrack.preferred(
                authored: [
                    RemoteCaptionTrack(
                        languageCode: "de",
                        displayName: "German",
                        kind: .authored
                    )
                ],
                automatic: [],
                originalLanguageCode: "uk"
            )
        )
        XCTAssertNil(
            RemoteCaptionTrack.preferred(
                authored: [authored],
                automatic: [automatic],
                originalLanguageCode: nil
            )
        )
    }

    func test_extractorFailureClassificationDistinguishesPrivateVideoFromExpiredSession() {
        XCTAssertEqual(
            BundledRemoteMediaExtractor.classifyFailure(Data("Private video".utf8)),
            .sourceUnavailable
        )
        XCTAssertEqual(
            BundledRemoteMediaExtractor.classifyFailure(Data("Sign in to confirm".utf8)),
            .authorizationRequired
        )
    }

    func test_metadataDecoder_selectsCompatibleAudioOnlyFormatAndOriginalCaptions() throws {
        let json = """
        {
          "id": "dQw4w9WgXcQ",
          "title": "A video",
          "uploader": "A channel",
          "duration": 125.5,
          "original_language": "uk",
          "is_live": false,
          "availability": "public",
          "formats": [
            {"format_id":"video","ext":"mp4","acodec":"none","vcodec":"avc1","tbr":900},
            {"format_id":"audio-low","ext":"m4a","acodec":"mp4a.40.2","vcodec":"none","abr":64},
            {"format_id":"audio-best","ext":"m4a","acodec":"mp4a.40.2","vcodec":"none","abr":128}
          ],
          "subtitles": {"uk":[{"name":"Ukrainian","ext":"vtt"}]},
          "automatic_captions": {"uk-orig":[{"name":"Ukrainian (auto-generated)","ext":"vtt"}]}
        }
        """
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        let metadata = try RemoteMediaMetadata.decodeYTDLPJSON(Data(json.utf8), expectedSource: source)

        XCTAssertEqual(metadata.source.title, "A video")
        XCTAssertEqual(metadata.source.channelName, "A channel")
        XCTAssertEqual(metadata.audioFormatID, "audio-best")
        XCTAssertEqual(metadata.preferredCaption?.kind, .authored)
        XCTAssertEqual(metadata.durationSeconds, 125.5, accuracy: 0.001)
    }

    func test_metadataDecoder_rejectsLiveAndMissingAudioOnlyFormats() throws {
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let liveJSON = """
        {"id":"dQw4w9WgXcQ","title":"Live","duration":1,"is_live":true,"formats":[]}
        """
        let videoOnlyJSON = """
        {"id":"dQw4w9WgXcQ","title":"Video","duration":1,"is_live":false,
         "formats":[{"format_id":"video","ext":"mp4","acodec":"none","vcodec":"avc1"}]}
        """

        XCTAssertThrowsError(try RemoteMediaMetadata.decodeYTDLPJSON(Data(liveJSON.utf8), expectedSource: source)) {
            XCTAssertEqual($0 as? RemoteMediaExtractorError, .unsupportedLiveStream)
        }
        XCTAssertThrowsError(try RemoteMediaMetadata.decodeYTDLPJSON(
            Data(videoOnlyJSON.utf8),
            expectedSource: source
        )) {
            XCTAssertEqual($0 as? RemoteMediaExtractorError, .noAudioOnlyStream)
        }
    }

    func test_webVTTParser_removesTimingMarkupAndRepeatedCaptionFrames() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        <c>Привіт</c>

        00:00:01.000 --> 00:00:02.000
        <c>Привіт</c>

        00:00:02.000 --> 00:00:03.000
        світе
        """

        XCTAssertEqual(WebVTTTranscriptParser.parse(vtt), "Привіт\nсвіте")
    }

    func test_chromeProfileDiscovery_returnsOnlyExistingProfileDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyChromeProfiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Default"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Profile 2"),
            withIntermediateDirectories: true
        )
        let localState = """
        {"profile":{"info_cache":{
          "Default":{"name":"Roman"},
          "Profile 2":{"name":"Work"},
          "Profile 9":{"name":"Deleted"}
        }}}
        """
        try Data(localState.utf8).write(to: root.appendingPathComponent("Local State"))

        let profiles = ChromeProfileStore.discover(in: root)

        XCTAssertEqual(profiles.map(\.id), ["Default", "Profile 2"])
        XCTAssertEqual(profiles.map(\.name), ["Roman", "Work"])
    }

    func test_runtimeArguments_useSelectedChromeProfileBundledDenoAndExactAudioFormat() throws {
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let profile = ChromeProfile(id: "Profile 2", name: "Work")
        let denoURL = URL(fileURLWithPath: "/Applications/Diduny.app/Contents/Resources/deno")

        let metadata = BundledRemoteMediaExtractor.metadataArguments(
            source: source,
            profile: profile,
            denoURL: denoURL
        )
        let download = BundledRemoteMediaExtractor.downloadArguments(
            source: source,
            profile: profile,
            denoURL: denoURL,
            audioFormatID: "audio-best",
            outputTemplate: "/tmp/source.%(ext)s"
        )

        XCTAssertTrue(metadata.contains("chrome:Profile 2"))
        XCTAssertTrue(metadata.contains("deno:\(denoURL.path)"))
        XCTAssertTrue(metadata.contains("--dump-single-json"))
        XCTAssertTrue(download.contains("audio-best"))
        XCTAssertTrue(download.contains("--no-playlist"))
        XCTAssertFalse(download.contains(where: { $0.contains("bestvideo") }))
    }

    @MainActor
    func test_metadataFallsBackToPublicAccessWhenChromeCookieDatabaseIsUnreadable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyRemoteFallback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-yt-dlp")
        let script = """
        #!/bin/sh
        case " $* " in
          *" --cookies-from-browser "*)
            echo "ERROR: no such table: meta" >&2
            exit 1
            ;;
        esac
        printf '%s\\n' '{"id":"dQw4w9WgXcQ","title":"Public video","duration":1,"formats":[{"format_id":"audio","ext":"m4a","acodec":"mp4a.40.2","vcodec":"none"}]}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let extractor = BundledRemoteMediaExtractor(
            ytDLPURL: executable,
            denoURL: executable,
            temporaryDirectory: root
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        let metadata = try await extractor.metadata(
            for: source,
            profile: ChromeProfile(id: "Profile 1", name: "Personal")
        )

        XCTAssertEqual(metadata.source.title, "Public video")
        XCTAssertEqual(metadata.audioFormatID, "audio")
    }

    func test_remoteDuplicateMatcher_prefersProviderIdentityAndSupportsLegacyTitleDurationFallback() throws {
        let source = try RemoteMediaSourceMetadata(
            provider: YouTubeRemoteMediaSource.provider,
            mediaID: "dQw4w9WgXcQ",
            canonicalURL: XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")),
            title: "A Useful Video",
            channelName: "Channel"
        )
        let exact = makeRemoteRecording(
            sourceFileName: "different.mov",
            duration: 10,
            remoteSource: source
        )
        var legacy = makeRemoteRecording(
            sourceFileName: "A Useful Video.mp4",
            duration: 121.4,
            remoteSource: nil
        )

        XCTAssertTrue(RemoteRecordingDuplicateMatcher.matches(exact, metadata: source, durationSeconds: 999))
        XCTAssertTrue(RemoteRecordingDuplicateMatcher.matches(legacy, metadata: source, durationSeconds: 120))
        XCTAssertFalse(RemoteRecordingDuplicateMatcher.matches(legacy, metadata: source, durationSeconds: 124))

        legacy.status = .failed
        legacy.transcriptionText = nil
        legacy.sourceCaptionArtifacts = [
            TranscriptArtifact(
                text: "Reusable captions",
                languageCode: "en",
                provenance: .youtubeAuthored
            )
        ]
        XCTAssertTrue(RemoteRecordingDuplicateMatcher.matches(legacy, metadata: source, durationSeconds: 120))
    }

    private func makeRemoteRecording(
        sourceFileName: String,
        duration: TimeInterval,
        remoteSource: RemoteMediaSourceMetadata?
    ) -> Recording {
        Recording(
            id: UUID(),
            createdAt: Date(),
            type: .fileTranscription,
            audioFileName: "audio.m4a",
            durationSeconds: duration,
            fileSizeBytes: 10,
            status: .translated,
            transcriptionText: "Existing",
            sourceDevice: nil,
            sourceFileName: sourceFileName,
            remoteSource: remoteSource
        )
    }
}

@MainActor
final class YouTubeRemoteMediaE2ETests: XCTestCase {
    func test_examplePublicURLsRetrieveAudioWithSelectedChromeProfile() async throws {
        guard ProcessInfo.processInfo.environment["DIDUNY_YOUTUBE_E2E"] == "1" else {
            throw XCTSkip("Set DIDUNY_YOUTUBE_E2E=1 to run live YouTube acquisition")
        }
        let profileID = ProcessInfo.processInfo.environment["DIDUNY_CHROME_PROFILE"] ?? "Profile 1"
        let profile = ChromeProfile(id: profileID, name: profileID)
        let extractor = BundledRemoteMediaExtractor()
        let urls = [
            "https://www.youtube.com/watch?v=434cG4g5KLE",
            "https://youtu.be/Zdk_YgK0i58"
        ]

        for rawURL in urls {
            let source = try YouTubeRemoteMediaSource.normalize(rawURL)
            let metadata = try await extractor.metadata(for: source, profile: profile)
            let downloaded = try await extractor.downloadAudio(
                for: source,
                metadata: metadata,
                profile: profile,
                onProgress: { _ in }
            )
            defer { downloaded.removeTemporaryFiles() }
            let values = try downloaded.fileURL.resourceValues(forKeys: [.fileSizeKey])
            XCTAssertGreaterThan(values.fileSize ?? 0, 0, rawURL)
        }
    }
}

@MainActor
final class FileTranscriptionBatchServiceTests: XCTestCase {
    func test_add_skipsDuplicateURLsWithinActiveBatch() {
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let first = URL(fileURLWithPath: "/tmp/first.mov")

        service.add(urls: [first, first, URL(fileURLWithPath: "/tmp/second.mp3")])

        XCTAssertEqual(service.items.map(\.sourceURL), [first, URL(fileURLWithPath: "/tmp/second.mp3")])
    }

    func test_addRemoteSources_skipsRepeatedCanonicalVideoIDs() throws {
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: BatchTestRemoteExtractor(),
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        service.add(remoteSources: [source, source])

        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.remoteSource?.mediaID, "dQw4w9WgXcQ")
    }

    func test_remoteAuthorizationPausesWholeBatchAndExplicitRetryCompletes() async throws {
        let extractor = BatchTestRemoteExtractor(metadataAuthorizationFailureCount: 1)
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let first = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let second = try YouTubeRemoteMediaSource.normalize("https://youtu.be/aqz-KE-bpKQ")

        service.beginBatch(remoteSources: [first, second])
        try await waitUntil {
            !service.isProcessing
                && service.items.allSatisfy { $0.status == .authorizationPaused }
        }

        XCTAssertEqual(extractor.downloadCallCount, 0)
        service.retryAuthorization()
        try await waitUntil { !service.isProcessing && service.completedCount == 2 }

        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
        XCTAssertGreaterThanOrEqual(extractor.metadataCallCount, 3)
    }

    func test_stopBatchDuringRemotePreflightMarksItemsCancelledWithoutAcquisition() async throws {
        let extractor = BatchTestRemoteExtractor(metadataDelay: .milliseconds(500))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        service.beginBatch(remoteSources: [source])
        try await waitUntil { service.items.first?.status == .checkingLink }
        service.cancelAll()
        try await waitUntil { !service.isProcessing }

        XCTAssertEqual(service.items.first?.status, .cancelled)
        XCTAssertEqual(extractor.downloadCallCount, 0)
    }

    func test_stopBatchCancelsMetadataRequestsWaitingForPermit() async throws {
        let extractor = BatchTestRemoteExtractor(metadataDelay: .milliseconds(500))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let ids = ["dQw4w9WgXcQ", "aqz-KE-bpKQ", "M7lc1UVf-VE", "jNQXAC9IVRw"]
        let sources = try ids.map {
            try YouTubeRemoteMediaSource.normalize("https://youtu.be/\($0)")
        }

        service.beginBatch(remoteSources: sources)
        try await waitUntil { extractor.metadataCallCount == 3 }
        service.cancelAll()
        try await waitUntil { !service.isProcessing }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(extractor.metadataCallCount, 3)
        XCTAssertEqual(extractor.downloadCallCount, 0)
        XCTAssertTrue(service.items.allSatisfy { $0.status == .cancelled })
    }

    func test_remoteCaptionSurvivesGeneratedTranscriptFailureAsPartialResult() async throws {
        let caption = TranscriptArtifact(
            text: "Provider captions",
            languageCode: "uk",
            provenance: .youtubeAuthored
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(failureCount: 1),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: BatchTestRemoteExtractor(caption: caption),
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        service.beginBatch(remoteSources: [source])
        try await waitUntil { !service.isProcessing && service.finishedCount == 1 }

        XCTAssertEqual(service.items.first?.status, .partialResult)
        XCTAssertEqual(service.items.first?.sourceCaptionArtifacts, [caption])
        XCTAssertNil(service.items.first?.transcriptionText)
    }

    func test_remoteTranscriptionPersistsTimedPhraseSegments() async throws {
        let segments = [
            TimedTranscriptSegment(
                startMilliseconds: 1200,
                endMilliseconds: 2000,
                text: "First thought."
            )
        ]
        let transcriber = BatchTestTranscriber(
            transcript: GeneratedTranscript(text: "First thought.", segments: segments)
        )
        let store = BatchTestRecordingStore(storesRemoteAudio: true)
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: store,
            remoteExtractor: BatchTestRemoteExtractor(),
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        service.beginBatch(remoteSources: [source])
        try await waitUntil { !service.isProcessing && service.finishedCount == 1 }

        XCTAssertEqual(store.completedTranscript?.text, "First thought.")
        XCTAssertEqual(store.completedTranscript?.segments, segments)
    }

    func test_remoteCaptionRetryDoesNotRegenerateCompletedTranscript() async throws {
        let caption = TranscriptArtifact(
            text: "Provider captions",
            languageCode: "uk",
            provenance: .youtubeAuthored
        )
        let extractor = BatchTestRemoteExtractor(
            caption: caption,
            captionFailureCount: 1
        )
        let transcriber = BatchTestTranscriber()
        let store = BatchTestRecordingStore(storesRemoteAudio: true)
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: store,
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")

        service.beginBatch(remoteSources: [source])
        try await waitUntil { !service.isProcessing && service.finishedCount == 1 }
        XCTAssertEqual(service.items.first?.status, .partialResult)
        XCTAssertNotNil(service.items.first?.transcriptionText)

        service.retryFailed()
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }

        XCTAssertEqual(transcriber.transcribedFileNames.count, 1)
        XCTAssertEqual(service.items.first?.sourceCaptionArtifacts, [caption])
        XCTAssertEqual(store.updatedCaptionArtifacts, [caption])
    }

    func test_remoteAcquisitionNeverExceedsTwoConcurrentDownloads() async throws {
        let extractor = BatchTestRemoteExtractor(downloadDelay: .milliseconds(80))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(delay: .milliseconds(80)),
            recordingStore: BatchTestRecordingStore(),
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let ids = ["dQw4w9WgXcQ", "aqz-KE-bpKQ", "M7lc1UVf-VE", "jNQXAC9IVRw"]
        let sources = try ids.map {
            try YouTubeRemoteMediaSource.normalize("https://youtu.be/\($0)")
        }

        service.beginBatch(remoteSources: sources)
        try await waitUntil { !service.isProcessing && service.completedCount == 4 }

        XCTAssertEqual(extractor.maximumConcurrentDownloadCount, 2)
    }

    func test_addRemoteSource_reusesProviderIdentityWithoutAcquisition() throws {
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let recordingID = UUID()
        let extractor = BatchTestRemoteExtractor()
        let caption = TranscriptArtifact(
            text: "Existing captions",
            languageCode: "en",
            provenance: .youtubeAuthored
        )
        let store = BatchTestRecordingStore(
            remoteDuplicate: BatchTranscriptionDuplicate(
                recordingID: recordingID,
                transcriptionText: "Existing transcript",
                durationSeconds: 90,
                sourceCaptionArtifacts: [caption]
            ),
            matchingRemoteMediaID: source.mediaID
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: store,
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(remoteSources: [source])

        XCTAssertEqual(service.items.first?.status, .duplicate)
        XCTAssertEqual(service.items.first?.recordingID, recordingID)
        XCTAssertEqual(extractor.metadataCallCount, 0)
    }

    func test_remoteDuplicateWithMissingCaptionsRetrievesOnlyCaptionArtifact() async throws {
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let caption = TranscriptArtifact(
            text: "New captions",
            languageCode: "en",
            provenance: .youtubeAuthored
        )
        let recordingID = UUID()
        let extractor = BatchTestRemoteExtractor(caption: caption)
        let transcriber = BatchTestTranscriber()
        let store = BatchTestRecordingStore(
            remoteDuplicate: BatchTranscriptionDuplicate(
                recordingID: recordingID,
                transcriptionText: "Existing transcript",
                durationSeconds: 90
            ),
            matchingRemoteMediaID: source.mediaID
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: store,
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(remoteSources: [source])
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }

        XCTAssertTrue(transcriber.transcribedFileNames.isEmpty)
        XCTAssertEqual(extractor.downloadCallCount, 0)
        XCTAssertEqual(service.items.first?.transcriptionText, "Existing transcript")
        XCTAssertEqual(service.items.first?.sourceCaptionArtifacts, [caption])
        XCTAssertEqual(store.updatedCaptionArtifacts, [caption])
    }

    func test_captionOnlyDuplicateWithoutStoredAudioIsReacquired() async throws {
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        let caption = TranscriptArtifact(
            text: "Existing captions",
            languageCode: "en",
            provenance: .youtubeAuthored
        )
        let extractor = BatchTestRemoteExtractor()
        let store = BatchTestRecordingStore(
            remoteDuplicate: BatchTranscriptionDuplicate(
                recordingID: UUID(),
                transcriptionText: nil,
                durationSeconds: 90,
                sourceCaptionArtifacts: [caption]
            ),
            matchingRemoteMediaID: source.mediaID
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: store,
            remoteExtractor: extractor,
            chromeProfile: { ChromeProfile(id: "Default", name: "Roman") },
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(remoteSources: [source])
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }

        XCTAssertEqual(extractor.downloadCallCount, 1)
        XCTAssertNotNil(service.items.first?.transcriptionText)
    }

    func test_cloudBatchProcessesUpToThreeFilesConcurrentlyAndCompletesOnce() async throws {
        let preparer = BatchTestPreparer()
        let transcriber = BatchTestTranscriber()
        let store = BatchTestRecordingStore()
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: store,
            settingsSnapshot: { .testValue },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mp4"),
            URL(fileURLWithPath: "/tmp/third.mp4"),
            URL(fileURLWithPath: "/tmp/fourth.mp4")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 4 }

        XCTAssertEqual(service.items.map(\.status), [.completed, .completed, .completed, .completed])
        XCTAssertEqual(transcriber.maximumConcurrentCount, 3)
        XCTAssertEqual(
            Set(transcriber.transcribedFileNames),
            Set(["first.m4a", "second.m4a", "third.m4a", "fourth.m4a"])
        )
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_localBatchProcessesOneFileAtATime() async throws {
        let transcriber = BatchTestTranscriber(delay: .milliseconds(80))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .localTestValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mp4")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(transcriber.maximumConcurrentCount, 1)
    }

    func test_add_reusesCompletedImportedRecordingAsDuplicate() throws {
        let recordingID = UUID()
        let preparer = BatchTestPreparer()
        let transcriber = BatchTestTranscriber()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("already-done-\(UUID().uuidString).mov")
        try Data("source video".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let store = BatchTestRecordingStore(
            duplicate: BatchTranscriptionDuplicate(
                recordingID: recordingID,
                transcriptionText: "Existing transcript",
                durationSeconds: 125
            ),
            matchingSourceIdentity: ImportedMediaIdentity(sourceURL: sourceURL)
        )
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: store,
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(urls: [sourceURL])

        XCTAssertEqual(service.items.first?.status, .duplicate)
        XCTAssertEqual(service.items.first?.recordingID, recordingID)
        XCTAssertEqual(service.items.first?.transcriptionText, "Existing transcript")
        XCTAssertEqual(service.items.first?.durationSeconds, 125)
        XCTAssertTrue(preparer.preparedSourceNames.isEmpty)
        XCTAssertTrue(transcriber.transcribedFileNames.isEmpty)
        XCTAssertFalse(service.isProcessing)
    }

    func test_add_doesNotReuseSameNameWithDifferentSourceSize() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyDuplicateTests-\(UUID().uuidString)")
        let firstURL = root.appendingPathComponent("first").appendingPathComponent("shared.mov")
        let secondURL = root.appendingPathComponent("second").appendingPathComponent("shared.mov")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: firstURL)
        try Data("different-size".utf8).write(to: secondURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BatchTestRecordingStore(
            duplicate: BatchTranscriptionDuplicate(
                recordingID: UUID(),
                transcriptionText: "Existing transcript",
                durationSeconds: 125
            ),
            matchingSourceIdentity: ImportedMediaIdentity(sourceURL: firstURL)
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: store,
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [firstURL, secondURL])

        XCTAssertEqual(service.items.map(\.status), [.duplicate, .queued])
    }

    func test_failedFileDoesNotStopRemainingBatch() async throws {
        let preparer = BatchTestPreparer(failingSourceNames: ["broken.mov"])
        let transcriber = BatchTestTranscriber()
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/broken.mov"),
            URL(fileURLWithPath: "/tmp/valid.mov")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(service.items[0].status, .failed)
        XCTAssertEqual(service.items[1].status, .completed)
        XCTAssertEqual(service.failedCount, 1)
        XCTAssertEqual(service.completedCount, 1)
    }

    func test_cancelAllCancelsCurrentAndPendingItems() async throws {
        let transcriber = BatchTestTranscriber(delay: .seconds(10))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mov")
        ])
        service.startIfNeeded()
        try await waitUntil { service.items.first?.status == .uploading }
        service.cancelAll()
        try await waitUntil { !service.isProcessing }

        XCTAssertEqual(service.items.map(\.status), [.cancelled, .cancelled])
    }

    func test_preflightFailureDoesNotStartAudioPreparation() {
        let preparer = BatchTestPreparer()
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: BatchTestTranscriber(preflightError: "Download a model first."),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()

        XCTAssertEqual(service.batchError, "Download a model first.")
        XCTAssertFalse(service.isProcessing)
        XCTAssertTrue(preparer.preparedSourceNames.isEmpty)
        XCTAssertEqual(service.items.first?.status, .queued)
    }

    func test_addWhileProcessingAppendsToTheRunningBatch() async throws {
        let transcriber = BatchTestTranscriber(waitsForRelease: true)
        defer { transcriber.releaseAll() }
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()
        try await waitUntil { service.items.first?.status == .uploading }
        service.add(urls: [URL(fileURLWithPath: "/tmp/second.mov")])
        service.startIfNeeded()
        try await waitUntil { transcriber.maximumConcurrentCount == 2 }
        transcriber.releaseAll()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(Set(transcriber.transcribedFileNames), Set(["first.m4a", "second.m4a"]))
        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
    }

    func test_addAfterProcessingAppendsWithoutClearingFinishedRows() async throws {
        let transcriber = BatchTestTranscriber()
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }
        service.add(urls: [URL(fileURLWithPath: "/tmp/second.mov")])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.completedCount == 2 }

        XCTAssertEqual(service.items.map(\.sourceURL.lastPathComponent), ["first.mov", "second.mov"])
        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_completedItemRemovesTemporaryPreparedAudio() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyBatchTests-\(UUID().uuidString)")
        let preparer = BatchTestPreparer(outputDirectory: outputDirectory)
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 1 }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("first.m4a").path))
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    func test_retryUsesInitialSettingsSnapshotAndPlaysSoundOnlyOnce() async throws {
        var snapshot = FileTranscriptionSettingsSnapshot.testValue
        let transcriber = BatchTestTranscriber(failureCount: 1)
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { snapshot },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        try await waitUntil { !service.isProcessing && service.failedCount == 1 }
        snapshot = FileTranscriptionSettingsSnapshot(
            provider: .local,
            languageHints: ["de"],
            localModelName: "changed-model"
        )

        service.retryFailed()
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }

        XCTAssertEqual(transcriber.receivedSettings.map(\.provider), [.cloud, .cloud])
        XCTAssertEqual(transcriber.receivedSettings.map(\.languageHints), [[], []])
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_activeItemExposesExactServerProgressWithoutInventingAggregateProgress() async throws {
        let transcriber = BatchTestTranscriber(
            delay: .milliseconds(500),
            progressUpdates: [JobProgressUpdate(status: .processing, progressPercent: 40)]
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let firstURL = URL(fileURLWithPath: "/tmp/first.mov")

        service.beginBatch(urls: [firstURL, URL(fileURLWithPath: "/tmp/second.mov")])
        try await waitUntil {
            service.items.first?.progressFraction == 0.4
                && service.items.first.map { service.isActive($0.id) } == true
        }

        XCTAssertEqual(service.progress, 0, accuracy: 0.001)
        XCTAssertNotNil(service.items.first?.startedAt)
        XCTAssertNil(service.items.first?.finishedAt)

        service.cancelAll()
        try await waitUntil { !service.isProcessing }
    }

    func test_statusWithoutProgressClearsPreviousServerPercentage() async throws {
        let transcriber = BatchTestTranscriber(
            delay: .milliseconds(500),
            progressUpdates: [
                JobProgressUpdate(status: .processing, progressPercent: 40),
                JobProgressUpdate(status: .finalizing)
            ]
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/progress.mov")])
        try await waitUntil { service.items.first?.status == .finalizing }

        XCTAssertNil(service.items.first?.progressFraction)

        service.cancelAll()
        try await waitUntil { !service.isProcessing }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for batch state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class BatchTestPreparer: FileTranscriptionBatchPreparing {
    private let failingSourceNames: Set<String>
    private let outputDirectory: URL
    private(set) var preparedSourceNames: [String] = []

    init(
        failingSourceNames: Set<String> = [],
        outputDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyBatchTests-\(UUID().uuidString)")
    ) {
        self.failingSourceNames = failingSourceNames
        self.outputDirectory = outputDirectory
    }

    func prepare(sourceURL: URL) async throws -> ImportedMediaAudioPreparer.PreparedAudio {
        preparedSourceNames.append(sourceURL.lastPathComponent)
        if failingSourceNames.contains(sourceURL.lastPathComponent) {
            throw BatchTestError.preparationFailed
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("m4a")
        try Data("test audio".utf8).write(to: outputURL)
        return ImportedMediaAudioPreparer.PreparedAudio(
            fileURL: outputURL,
            durationSeconds: 12
        )
    }
}

@MainActor
private final class BatchTestRemoteExtractor: RemoteMediaExtracting {
    private var remainingAuthorizationFailures: Int
    private var remainingCaptionFailures: Int
    private let caption: TranscriptArtifact?
    private let metadataDelay: Duration
    private let downloadDelay: Duration
    private(set) var metadataCallCount = 0
    private(set) var downloadCallCount = 0
    private(set) var maximumConcurrentDownloadCount = 0
    private var concurrentDownloadCount = 0

    init(
        metadataAuthorizationFailureCount: Int = 0,
        caption: TranscriptArtifact? = nil,
        captionFailureCount: Int = 0,
        metadataDelay: Duration = .zero,
        downloadDelay: Duration = .zero
    ) {
        remainingAuthorizationFailures = metadataAuthorizationFailureCount
        remainingCaptionFailures = captionFailureCount
        self.caption = caption
        self.metadataDelay = metadataDelay
        self.downloadDelay = downloadDelay
    }

    func metadata(
        for source: YouTubeRemoteMediaSource,
        profile _: ChromeProfile
    ) async throws -> RemoteMediaMetadata {
        metadataCallCount += 1
        if metadataDelay > .zero {
            try await Task.sleep(for: metadataDelay)
        }
        if remainingAuthorizationFailures > 0 {
            remainingAuthorizationFailures -= 1
            throw RemoteMediaExtractorError.authorizationRequired
        }
        return RemoteMediaMetadata(
            source: RemoteMediaSourceMetadata(
                provider: YouTubeRemoteMediaSource.provider,
                mediaID: source.mediaID,
                canonicalURL: source.canonicalURL,
                title: "Video \(source.mediaID)",
                channelName: "Channel"
            ),
            durationSeconds: 60,
            audioFormatID: "audio",
            estimatedAudioBytes: 1024,
            preferredCaption: caption.map {
                RemoteCaptionTrack(
                    languageCode: $0.languageCode,
                    displayName: $0.languageCode,
                    kind: $0.provenance == .youtubeAuthored ? .authored : .automatic
                )
            }
        )
    }

    func retrieveCaption(
        for _: YouTubeRemoteMediaSource,
        metadata _: RemoteMediaMetadata,
        profile _: ChromeProfile
    ) async throws -> TranscriptArtifact? {
        if remainingCaptionFailures > 0 {
            remainingCaptionFailures -= 1
            throw BatchTestError.captionFailed
        }
        return caption
    }

    func downloadAudio(
        for source: YouTubeRemoteMediaSource,
        metadata _: RemoteMediaMetadata,
        profile _: ChromeProfile,
        onProgress: @escaping @Sendable (RemoteDownloadProgress) -> Void
    ) async throws -> RemoteDownloadedAudio {
        downloadCallCount += 1
        concurrentDownloadCount += 1
        maximumConcurrentDownloadCount = max(
            maximumConcurrentDownloadCount,
            concurrentDownloadCount
        )
        defer { concurrentDownloadCount -= 1 }
        if downloadDelay > .zero {
            try await Task.sleep(for: downloadDelay)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyRemoteBatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(source.mediaID).m4a")
        try Data("remote audio".utf8).write(to: fileURL)
        onProgress(RemoteDownloadProgress(downloadedBytes: 12, totalBytes: 12))
        return RemoteDownloadedAudio(fileURL: fileURL, temporaryDirectory: directory)
    }
}

@MainActor
private final class BatchTestTranscriber: FileTranscriptionBatchTranscribing {
    private(set) var transcribedFileNames: [String] = []
    private(set) var receivedSettings: [FileTranscriptionSettingsSnapshot] = []
    private(set) var maximumConcurrentCount = 0
    private var concurrentCount = 0
    private var remainingFailures: Int
    private let delay: Duration
    private let preflightErrorMessage: String?
    private let progressUpdates: [JobProgressUpdate]
    private let waitsForRelease: Bool
    private let transcript: GeneratedTranscript?
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        delay: Duration = .milliseconds(20),
        preflightError: String? = nil,
        failureCount: Int = 0,
        progressUpdates: [JobProgressUpdate] = [],
        waitsForRelease: Bool = false,
        transcript: GeneratedTranscript? = nil
    ) {
        self.delay = delay
        preflightErrorMessage = preflightError
        remainingFailures = failureCount
        self.progressUpdates = progressUpdates
        self.waitsForRelease = waitsForRelease
        self.transcript = transcript
    }

    func preflightError(for _: FileTranscriptionSettingsSnapshot) -> String? {
        preflightErrorMessage
    }

    func transcribe(
        audioFileURL: URL,
        settings: FileTranscriptionSettingsSnapshot,
        source _: String,
        sourceDurationSeconds _: TimeInterval?,
        onUpdate: @escaping (JobProgressUpdate) -> Void
    ) async throws -> GeneratedTranscript {
        transcribedFileNames.append(audioFileURL.lastPathComponent)
        receivedSettings.append(settings)
        concurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
        defer { concurrentCount -= 1 }
        for update in progressUpdates {
            onUpdate(update)
            try await Task.sleep(for: .milliseconds(10))
        }
        if waitsForRelease {
            await withCheckedContinuation { releaseContinuations.append($0) }
        } else {
            try await Task.sleep(for: delay)
        }
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw BatchTestError.transcriptionFailed
        }
        return transcript ?? GeneratedTranscript(
            text: "Transcript for \(audioFileURL.lastPathComponent)"
        )
    }

    func releaseAll() {
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class BatchTestRecordingStore: FileTranscriptionBatchRecordingStoring {
    private let duplicate: BatchTranscriptionDuplicate?
    private let matchingSourceIdentity: ImportedMediaIdentity?
    private let remoteDuplicate: BatchTranscriptionDuplicate?
    private let matchingRemoteMediaID: String?
    private let storesRemoteAudio: Bool
    private var storedAudioURLs: [UUID: URL] = [:]
    private(set) var updatedCaptionArtifacts: [TranscriptArtifact] = []
    private(set) var completedTranscript: GeneratedTranscript?

    init(
        duplicate: BatchTranscriptionDuplicate? = nil,
        matchingSourceIdentity: ImportedMediaIdentity? = nil,
        remoteDuplicate: BatchTranscriptionDuplicate? = nil,
        matchingRemoteMediaID: String? = nil,
        storesRemoteAudio: Bool = false
    ) {
        self.duplicate = duplicate
        self.matchingSourceIdentity = matchingSourceIdentity
        self.remoteDuplicate = remoteDuplicate
        self.matchingRemoteMediaID = matchingRemoteMediaID
        self.storesRemoteAudio = storesRemoteAudio
    }

    func completedDuplicate(sourceIdentity: ImportedMediaIdentity) -> BatchTranscriptionDuplicate? {
        if let matchingSourceIdentity, matchingSourceIdentity != sourceIdentity {
            return nil
        }
        return duplicate
    }

    func completedDuplicate(remoteProvider _: String, mediaID: String) -> BatchTranscriptionDuplicate? {
        guard matchingRemoteMediaID == nil || matchingRemoteMediaID == mediaID else { return nil }
        return remoteDuplicate
    }

    func savePreparedAudio(
        at _: URL,
        durationSeconds _: TimeInterval,
        sourceIdentity _: ImportedMediaIdentity
    ) -> UUID? {
        nil
    }

    func savePreparedAudio(
        at audioURL: URL,
        durationSeconds _: TimeInterval,
        remoteMetadata _: RemoteMediaSourceMetadata,
        sourceCaptionArtifacts _: [TranscriptArtifact]
    ) -> UUID? {
        guard storesRemoteAudio else { return nil }
        let recordingID = UUID()
        let storedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyStoredRemote-\(recordingID.uuidString).m4a")
        try? FileManager.default.copyItem(at: audioURL, to: storedURL)
        storedAudioURLs[recordingID] = storedURL
        return recordingID
    }

    func audioFileURL(recordingID: UUID) -> URL? {
        storedAudioURLs[recordingID]
    }

    func updateSourceCaptionArtifacts(recordingID _: UUID, artifacts: [TranscriptArtifact]) {
        updatedCaptionArtifacts = artifacts
    }

    func markProcessing(recordingID _: UUID) {}
    func markCompleted(
        recordingID _: UUID,
        transcript: GeneratedTranscript,
        provenance _: GeneratedTranscriptProvenance?
    ) {
        completedTranscript = transcript
    }

    func markFailed(recordingID _: UUID, error _: String) {}
    func markUnprocessed(recordingID _: UUID) {}
}

private enum BatchTestError: Error {
    case preparationFailed
    case transcriptionFailed
    case captionFailed
}

private extension FileTranscriptionSettingsSnapshot {
    static let testValue = FileTranscriptionSettingsSnapshot(
        provider: .cloud,
        languageHints: [],
        localModelName: ""
    )

    static let localTestValue = FileTranscriptionSettingsSnapshot(
        provider: .local,
        languageHints: [],
        localModelName: "test-model"
    )
}
