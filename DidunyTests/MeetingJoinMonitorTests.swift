@testable import Diduny
import XCTest

@MainActor
final class MeetingJoinMonitorTests: XCTestCase {
    func test_stableNativeSignalEmitsOneJoinedEvent() {
        let monitor = MeetingJoinMonitor()
        let joinedZoom = MeetingSignal(
            client: .zoom,
            source: .native,
            isInputActive: true,
            isOutputActive: true,
            hasCallWindow: false,
            isFrontmostCallWindow: false
        )
        let startedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(monitor.ingest([joinedZoom], at: startedAt))
        guard case let .joined(meeting) = monitor.ingest([joinedZoom], at: startedAt.addingTimeInterval(1)) else {
            return XCTFail("Expected a joined event after a stable signal")
        }

        XCTAssertEqual(meeting.client, .zoom)
        XCTAssertNil(monitor.ingest([joinedZoom], at: startedAt.addingTimeInterval(2)))
    }

    func test_sessionEndsAfterThirtySecondsWithoutSignal_andNextMeetingCanJoin() {
        let monitor = MeetingJoinMonitor()
        let joinedTeams = MeetingSignal(
            client: .teams,
            source: .native,
            isInputActive: true,
            isOutputActive: true,
            hasCallWindow: false,
            isFrontmostCallWindow: false
        )
        let startedAt = Date(timeIntervalSince1970: 2_000)

        XCTAssertNil(monitor.ingest([joinedTeams], at: startedAt))
        guard case let .joined(firstMeeting) = monitor.ingest(
            [joinedTeams],
            at: startedAt.addingTimeInterval(1)
        ) else {
            return XCTFail("Expected the first meeting to join")
        }
        XCTAssertNil(monitor.ingest([], at: startedAt.addingTimeInterval(2)))

        XCTAssertEqual(
            monitor.ingest([], at: startedAt.addingTimeInterval(31)),
            .ended(firstMeeting)
        )

        XCTAssertNil(monitor.ingest([joinedTeams], at: startedAt.addingTimeInterval(32)))
        guard case let .joined(secondMeeting) = monitor.ingest(
            [joinedTeams],
            at: startedAt.addingTimeInterval(33)
        ) else {
            return XCTFail("Expected a later meeting to join")
        }
        XCTAssertNotEqual(firstMeeting.id, secondMeeting.id)
    }

    func test_multipleCandidatesPreferFrontmostCallWindow() {
        let monitor = MeetingJoinMonitor()
        let backgroundDuplex = MeetingSignal(
            client: .slackHuddle,
            source: .native,
            isInputActive: true,
            isOutputActive: true,
            hasCallWindow: true,
            isFrontmostCallWindow: false
        )
        let frontmostCall = MeetingSignal(
            client: .webex,
            source: .native,
            isInputActive: false,
            isOutputActive: true,
            hasCallWindow: true,
            isFrontmostCallWindow: true
        )
        let startedAt = Date(timeIntervalSince1970: 3_000)
        let signals = [backgroundDuplex, frontmostCall]

        XCTAssertNil(monitor.ingest(signals, at: startedAt))
        guard case let .joined(meeting) = monitor.ingest(signals, at: startedAt.addingTimeInterval(1)) else {
            return XCTFail("Expected the preferred meeting to join")
        }

        XCTAssertEqual(meeting.client, .webex)
    }

    func test_disabledMonitorDoesNotPollOrEmitEvents() async {
        let key = "meetingSuggestionsEnabled"
        let storedValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let storedValue {
                UserDefaults.standard.set(storedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        SettingsStorage.shared.meetingSuggestionsEnabled = false
        var pollCount = 0
        var events: [MeetingPresenceEvent] = []
        let monitor = MeetingJoinMonitor(
            snapshot: {
                pollCount += 1
                return []
            },
            now: Date.init,
            sleep: { _ in }
        )

        monitor.start { events.append($0) }
        await Task.yield()
        monitor.stop()

        XCTAssertEqual(pollCount, 0)
        XCTAssertTrue(events.isEmpty)
    }

    func test_startedMonitorUsesInjectedClockAndSleepToEmitOneJoin() async {
        let key = "meetingSuggestionsEnabled"
        let storedValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let storedValue {
                UserDefaults.standard.set(storedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        SettingsStorage.shared.meetingSuggestionsEnabled = true
        let startedAt = Date(timeIntervalSince1970: 5_000)
        var tick = 0
        var pollCount = 0
        var events: [MeetingPresenceEvent] = []
        let signal = MeetingSignal(
            client: .zoom,
            source: .native,
            isInputActive: true,
            isOutputActive: true,
            hasCallWindow: false,
            isFrontmostCallWindow: false
        )
        let monitor = MeetingJoinMonitor(
            snapshot: {
                pollCount += 1
                return [signal]
            },
            now: { startedAt.addingTimeInterval(TimeInterval(tick)) },
            sleep: { _ in
                tick += 1
                if tick == 2 { throw CancellationError() }
            }
        )

        monitor.start { events.append($0) }
        for _ in 0 ..< 20 where events.isEmpty {
            await Task.yield()
        }
        monitor.stop()

        XCTAssertEqual(pollCount, 2)
        XCTAssertEqual(events.count, 1)
        guard case .joined = events.first else {
            return XCTFail("Expected one joined event")
        }
    }

    func test_browserRequiresMeetingWindowAndAudioActivity() {
        let chromeAudio = MeetingAudioProcessSnapshot(
            bundleIdentifier: BrowserKind.chrome.bundleIdentifier,
            isInputActive: true,
            isOutputActive: true
        )
        let meetWindow = MeetingWindowSnapshot(
            bundleIdentifier: BrowserKind.chrome.bundleIdentifier,
            title: "Weekly sync - Google Meet",
            isFrontmost: true
        )

        XCTAssertTrue(MeetingJoinMonitor.signals(audio: [chromeAudio], windows: []).isEmpty)
        XCTAssertTrue(MeetingJoinMonitor.signals(audio: [], windows: [meetWindow]).isEmpty)

        XCTAssertEqual(
            MeetingJoinMonitor.signals(audio: [chromeAudio], windows: [meetWindow]),
            [
                MeetingSignal(
                    client: .googleMeet,
                    source: .browser,
                    isInputActive: true,
                    isOutputActive: true,
                    hasCallWindow: true,
                    isFrontmostCallWindow: true
                )
            ]
        )
    }

    func test_nativeBundleProfilesMapDuplexAudioToExpectedClients() {
        let profiles: [(String, MeetingClient)] = [
            ("us.zoom.xos", .zoom),
            ("com.microsoft.teams2", .teams),
            ("com.microsoft.teams", .teams),
            ("Cisco-Systems.Spark", .webex),
            ("com.cisco.webexmeetingsapp", .webex),
            ("com.tinyspeck.slackmacgap", .slackHuddle),
            ("com.apple.FaceTime", .faceTime)
        ]

        for (bundleIdentifier, client) in profiles {
            let signals = MeetingJoinMonitor.signals(
                audio: [
                    MeetingAudioProcessSnapshot(
                        bundleIdentifier: bundleIdentifier,
                        isInputActive: true,
                        isOutputActive: true
                    )
                ],
                windows: []
            )

            XCTAssertEqual(signals.map(\.client), [client], bundleIdentifier)
        }
    }

    func test_shortSignalFlapDoesNotJoin() {
        let monitor = MeetingJoinMonitor()
        let signal = MeetingSignal(
            client: .faceTime,
            source: .native,
            isInputActive: true,
            isOutputActive: true,
            hasCallWindow: false,
            isFrontmostCallWindow: false
        )
        let startedAt = Date(timeIntervalSince1970: 4_000)

        XCTAssertNil(monitor.ingest([signal], at: startedAt))
        XCTAssertNil(monitor.ingest([], at: startedAt.addingTimeInterval(1)))
        XCTAssertNil(monitor.ingest([signal], at: startedAt.addingTimeInterval(2)))
    }

    func test_stableBrowserSignalEmitsOneJoinedEvent() {
        let monitor = MeetingJoinMonitor()
        let meet = MeetingSignal(
            client: .googleMeet,
            source: .browser,
            isInputActive: true,
            isOutputActive: false,
            hasCallWindow: true,
            isFrontmostCallWindow: true
        )
        let startedAt = Date(timeIntervalSince1970: 6_000)

        XCTAssertNil(monitor.ingest([meet], at: startedAt))
        guard case let .joined(meeting) = monitor.ingest([meet], at: startedAt.addingTimeInterval(1)) else {
            return XCTFail("Expected a browser meeting to join")
        }
        XCTAssertEqual(meeting.client, .googleMeet)
        XCTAssertNil(monitor.ingest([meet], at: startedAt.addingTimeInterval(2)))
    }

    func test_googleMeetMappingUsesEverySupportedBrowserFamily() {
        for browser in BrowserKind.allCases {
            let audioBundleIdentifier = browser == .safari
                ? "com.apple.WebKit.WebContent"
                : browser.bundleIdentifier + ".helper"
            let signals = MeetingJoinMonitor.signals(
                audio: [
                    MeetingAudioProcessSnapshot(
                        bundleIdentifier: audioBundleIdentifier,
                        isInputActive: true,
                        isOutputActive: false
                    )
                ],
                windows: [
                    MeetingWindowSnapshot(
                        bundleIdentifier: browser.bundleIdentifier,
                        title: "Product review - Google Meet",
                        isFrontmost: false
                    )
                ]
            )

            XCTAssertEqual(signals.map(\.client), [.googleMeet], browser.rawValue)
        }
    }

    func test_systemWithoutProcessSelectorsRequiresCallWindowAndActiveSystemInput() {
        let zoomWindow = MeetingWindowSnapshot(
            bundleIdentifier: "us.zoom.xos",
            title: "Zoom Meeting",
            isFrontmost: false
        )

        XCTAssertTrue(
            MeetingJoinMonitor.signals(
                audio: [],
                windows: [zoomWindow],
                supportsProcessActivity: false,
                systemInputActive: false
            ).isEmpty
        )
        XCTAssertEqual(
            MeetingJoinMonitor.signals(
                audio: [],
                windows: [zoomWindow],
                supportsProcessActivity: false,
                systemInputActive: true
            ).map(\.client),
            [.zoom]
        )
    }
}
