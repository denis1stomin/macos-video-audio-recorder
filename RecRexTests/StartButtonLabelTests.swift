import XCTest
@testable import RecRex

final class StartButtonLabelTests: XCTestCase {
    func testVideoOnShowsSelectSourceLabel() {
        XCTAssertEqual(StartButtonLabel.text(recordVideo: true), "Select video source")
    }

    func testVideoOffShowsAudioOnlyLabel() {
        XCTAssertEqual(StartButtonLabel.text(recordVideo: false), "Start recording only audio")
    }
}
