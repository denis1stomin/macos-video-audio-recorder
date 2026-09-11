import XCTest
@testable import RecRex

final class SegmentSchedulerTests: XCTestCase {
    func testDoesNotRollOverBeforeDurationElapsed() {
        let start = Date()
        let now = start.addingTimeInterval(89 * 60)
        XCTAssertFalse(SegmentScheduler.shouldRollOver(segmentStart: start, now: now))
    }

    func testRollsOverAtExactDuration() {
        let start = Date()
        let now = start.addingTimeInterval(SegmentScheduler.segmentDuration)
        XCTAssertTrue(SegmentScheduler.shouldRollOver(segmentStart: start, now: now))
    }

    func testRollsOverAfterDurationElapsed() {
        let start = Date()
        let now = start.addingTimeInterval(91 * 60)
        XCTAssertTrue(SegmentScheduler.shouldRollOver(segmentStart: start, now: now))
    }

    func testRespectsCustomDuration() {
        let start = Date()
        let now = start.addingTimeInterval(10 * 60)
        XCTAssertTrue(SegmentScheduler.shouldRollOver(segmentStart: start, now: now, duration: 5 * 60))
        XCTAssertFalse(SegmentScheduler.shouldRollOver(segmentStart: start, now: now, duration: 20 * 60))
    }
}
