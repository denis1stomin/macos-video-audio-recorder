import XCTest
@testable import RecRex

final class FileNamingTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testIsoTimestampFormat() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 32, second: 5))!
        XCTAssertEqual(FileNaming.isoTimestamp(for: date, calendar: utcCalendar), "2026-09-11T14-32-05")
    }

    func testBaseFileName() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        XCTAssertEqual(FileNaming.baseFileName(for: date), "Recording " + FileNaming.isoTimestamp(for: date))
    }

    func testSegmentFileNameFirstSegmentHasNoSuffix() {
        XCTAssertEqual(FileNaming.segmentFileName(baseName: "Recording X", segmentIndex: 1), "Recording X.mp4")
    }

    func testSegmentFileNameLaterSegmentsGetPartSuffix() {
        XCTAssertEqual(FileNaming.segmentFileName(baseName: "Recording X", segmentIndex: 2), "Recording X part2.mp4")
        XCTAssertEqual(FileNaming.segmentFileName(baseName: "Recording X", segmentIndex: 3), "Recording X part3.mp4")
    }

    func testAvailableURLReturnsProposedWhenNoCollision() {
        let url = URL(fileURLWithPath: "/tmp/Recording.mp4")
        let result = FileNaming.availableURL(for: url, fileExists: { _ in false })
        XCTAssertEqual(result, url)
    }

    func testAvailableURLAppendsFinderStyleSuffixOnCollision() {
        let url = URL(fileURLWithPath: "/tmp/Recording.mp4")
        let existing: Set<String> = ["/tmp/Recording.mp4", "/tmp/Recording (2).mp4"]
        let result = FileNaming.availableURL(for: url, fileExists: { existing.contains($0.path) })
        XCTAssertEqual(result.path, "/tmp/Recording (3).mp4")
    }
}
