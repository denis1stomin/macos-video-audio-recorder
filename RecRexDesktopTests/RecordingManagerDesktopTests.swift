import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import RecRex

/// Exercises RecordingManager against the real ScreenCaptureKit/AVFoundation stack — actually
/// capturing a few seconds of screen + system audio and asserting on the resulting file.
///
/// This needs real Screen Recording (and, for mic tests, Microphone) permission granted to
/// whatever signing identity built this test bundle, so it only runs locally via
/// `make test-desktop` (or the RecRexDesktopTests scheme in Xcode) — never in CI, which has no
/// way to grant that permission on a headless runner.
final class RecordingManagerDesktopTests: XCTestCase {
    func testVideoAndSystemAudioProducesNonEmptyPlayableFile() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw XCTSkip("No capturable display in this environment")
        }

        let manager = RecordingManager()
        let settings = RecordingSettings(
            videoSource: .display(DisplaySource(display: display)),
            captureSystemAudio: true,
            captureMicrophone: false
        )

        try await manager.start(settings: settings)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let urls = await manager.stop()

        addTeardownBlock {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }

        XCTAssertFalse(urls.isEmpty, "Expected at least one recorded segment")

        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int ?? 0
            XCTAssertGreaterThan(size, 10_000, "\(url.lastPathComponent) should be a real recording, not an empty/near-empty file")

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertGreaterThan(duration.seconds, 0, "\(url.lastPathComponent) should have non-zero duration")

            let tracks = try await asset.load(.tracks)
            XCTAssertTrue(tracks.contains { $0.mediaType == .video }, "Expected a video track")
            XCTAssertTrue(tracks.contains { $0.mediaType == .audio }, "Expected a system-audio track")
        }
    }

    func testMicrophoneOnlyProducesNonEmptyPlayableFile() async throws {
        let manager = RecordingManager()
        let settings = RecordingSettings(
            videoSource: nil,
            captureSystemAudio: false,
            captureMicrophone: true
        )

        try await manager.start(settings: settings)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let urls = await manager.stop()

        addTeardownBlock {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }

        XCTAssertFalse(urls.isEmpty, "Expected at least one recorded segment (this is the mic-only bug we fixed — regressing this means needsScreenCaptureKit broke again)")

        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes[.size] as? Int ?? 0
            XCTAssertGreaterThan(size, 1_000, "\(url.lastPathComponent) should be a real recording, not an empty/near-empty file")
        }
    }
}
