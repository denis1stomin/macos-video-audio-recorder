import Foundation

enum SegmentScheduler {
    static let segmentDuration: TimeInterval = 90 * 60

    static func shouldRollOver(segmentStart: Date, now: Date, duration: TimeInterval = segmentDuration) -> Bool {
        now.timeIntervalSince(segmentStart) >= duration
    }
}
