import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import RexGrab

/// Exercises RecordingManager against the real ScreenCaptureKit/AVFoundation stack — actually
/// capturing a few seconds of real screen/system-audio/microphone content and asserting on the
/// resulting file, across every combination of video/system-audio/microphone the app's own UI
/// can produce (per CLAUDE.md: "all combinations ... are supported"). The one combination left
/// out is all three off, which isn't reachable through the app's UI (there's nothing to record).
///
/// Every video-capturing combination runs twice: once per connected display (so multi-monitor
/// setups are exercised, not just the first display) and once against a randomly chosen
/// capturable window, covering both SCContentFilter code paths RecordingManager uses.
///
/// This needs real Screen Recording (and, for mic tests, Microphone) permission granted to
/// whatever signing identity built this test bundle, so it only runs locally via
/// `make test-desktop` (or the RexGrabDesktopTests scheme in Xcode) — never in CI, which has no
/// way to grant that permission on a headless runner.
final class RecordingManagerDesktopTests: XCTestCase {
    func testVideoOnly() async throws {
        for display in try await allDisplaySources() {
            try await recordAndAssert(
                settings: RecordingSettings(videoSource: .display(display), captureSystemAudio: false, captureMicrophone: false),
                expectedVideoTracks: 1,
                expectedAudioTracks: 0
            )
        }
    }

    func testVideoAndSystemAudio() async throws {
        for display in try await allDisplaySources() {
            try await recordAndAssert(
                settings: RecordingSettings(videoSource: .display(display), captureSystemAudio: true, captureMicrophone: false),
                expectedVideoTracks: 1,
                expectedAudioTracks: 1
            )
        }
    }

    func testVideoAndMicrophone() async throws {
        for display in try await allDisplaySources() {
            try await recordAndAssert(
                settings: RecordingSettings(videoSource: .display(display), captureSystemAudio: false, captureMicrophone: true),
                expectedVideoTracks: 1,
                expectedAudioTracks: 1
            )
        }
    }

    func testVideoSystemAudioAndMicrophone() async throws {
        for display in try await allDisplaySources() {
            try await recordAndAssert(
                settings: RecordingSettings(videoSource: .display(display), captureSystemAudio: true, captureMicrophone: true),
                expectedVideoTracks: 1,
                expectedAudioTracks: 2
            )
        }
    }

    func testWindowVideoOnly() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(
                videoSource: .window(try await randomWindowSource()),
                captureSystemAudio: false,
                captureMicrophone: false
            ),
            expectedVideoTracks: 1,
            expectedAudioTracks: 0,
            // Window content size is unpredictable (could be a tiny toolbar/status window), so
            // this stays lenient — duration/track checks are the real correctness signal here.
            minimumFileSize: 1_000
        )
    }

    func testWindowVideoAndSystemAudio() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(
                videoSource: .window(try await randomWindowSource()),
                captureSystemAudio: true,
                captureMicrophone: false
            ),
            expectedVideoTracks: 1,
            expectedAudioTracks: 1,
            minimumFileSize: 1_000
        )
    }

    func testWindowVideoAndMicrophone() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(
                videoSource: .window(try await randomWindowSource()),
                captureSystemAudio: false,
                captureMicrophone: true
            ),
            expectedVideoTracks: 1,
            expectedAudioTracks: 1,
            minimumFileSize: 1_000
        )
    }

    func testWindowVideoSystemAudioAndMicrophone() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(
                videoSource: .window(try await randomWindowSource()),
                captureSystemAudio: true,
                captureMicrophone: true
            ),
            expectedVideoTracks: 1,
            expectedAudioTracks: 2,
            minimumFileSize: 1_000
        )
    }

    func testSystemAudioOnly() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(videoSource: nil, captureSystemAudio: true, captureMicrophone: false),
            expectedVideoTracks: 0,
            expectedAudioTracks: 1,
            minimumFileSize: 1_000
        )
    }

    func testMicrophoneOnly() async throws {
        // This combination is also the mic-only bug we fixed (needsScreenCaptureKit forgot
        // captureMicrophone, so the ScreenCaptureKit stream never started) — regressing here
        // means that bug came back.
        try await recordAndAssert(
            settings: RecordingSettings(videoSource: nil, captureSystemAudio: false, captureMicrophone: true),
            expectedVideoTracks: 0,
            expectedAudioTracks: 1,
            minimumFileSize: 1_000
        )
    }

    func testSystemAudioAndMicrophone() async throws {
        try await recordAndAssert(
            settings: RecordingSettings(videoSource: nil, captureSystemAudio: true, captureMicrophone: true),
            expectedVideoTracks: 0,
            expectedAudioTracks: 2,
            minimumFileSize: 1_000
        )
    }

    // MARK: - Helpers

    /// Every connected display, so multi-monitor setups actually get exercised instead of only
    /// ever testing the first display.
    private func allDisplaySources() async throws -> [DisplaySource] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw XCTSkip("No capturable display in this environment")
        }
        return content.displays.map(DisplaySource.init)
    }

    /// Picks a random capturable window, mirroring AppState.beginSourceSelection's own filtering
    /// (a normal app window — not a menu bar item or the desktop, has a title, isn't RexGrab's own
    /// window) — a random pick rather than always "first" so this exercises whatever window
    /// happens to be open locally instead of depending on a specific one existing.
    private func randomWindowSource() async throws -> WindowSource {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier
        let candidates = content.windows
            .filter { $0.windowLayer == 0 }
            .filter { $0.owningApplication != nil }
            .filter { $0.title?.isEmpty == false }
            .filter { $0.owningApplication?.bundleIdentifier != ownBundleID }
        guard let window = candidates.randomElement() else {
            throw XCTSkip("No capturable window in this environment")
        }
        return WindowSource(window: window)
    }

    private func recordAndAssert(
        settings: RecordingSettings,
        expectedVideoTracks: Int,
        expectedAudioTracks: Int,
        minimumFileSize: Int = 10_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let manager = RecordingManager()
        try await manager.start(settings: settings)
        // Captured right after start(), once RecordingManager has derived it from the real
        // SCContentFilter — this is the pixel size the encoder was actually configured for.
        let expectedPixelSize = manager.videoPixelSize
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let urls = await manager.stop()

        addTeardownBlock {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }

        XCTAssertFalse(urls.isEmpty, "Expected at least one recorded segment", file: file, line: line)

        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int ?? 0
            XCTAssertGreaterThan(
                size, minimumFileSize,
                "\(url.lastPathComponent) should be a real recording, not an empty/near-empty file",
                file: file, line: line
            )

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertGreaterThan(duration.seconds, 0, "\(url.lastPathComponent) should have non-zero duration", file: file, line: line)

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            let audioTrackCount = tracks.filter { $0.mediaType == .audio }.count
            XCTAssertEqual(
                videoTracks.count, expectedVideoTracks,
                "Unexpected video track count in \(url.lastPathComponent)",
                file: file, line: line
            )
            XCTAssertEqual(
                audioTrackCount, expectedAudioTracks,
                "Unexpected audio track count in \(url.lastPathComponent)",
                file: file, line: line
            )

            // The encoded frame must exactly match the real captured content's pixel size — a
            // mismatch here (e.g. from guessing a fixed Retina scale instead of asking
            // SCContentFilter for the real size) is what produces black letterboxing/pillarboxing
            // around a window smaller than its screen.
            if let videoTrack = videoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                XCTAssertEqual(
                    Int(naturalSize.width), expectedPixelSize.width,
                    "\(url.lastPathComponent) video width doesn't match the real captured content size — likely letterboxing",
                    file: file, line: line
                )
                XCTAssertEqual(
                    Int(naturalSize.height), expectedPixelSize.height,
                    "\(url.lastPathComponent) video height doesn't match the real captured content size — likely letterboxing",
                    file: file, line: line
                )
            }
        }
    }
}
