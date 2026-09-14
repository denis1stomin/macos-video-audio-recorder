import Foundation

enum FileNaming {
    static func isoTimestamp(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }

    static func baseFileName(for date: Date) -> String {
        "Recording \(isoTimestamp(for: date))"
    }

    static func segmentFileName(baseName: String, segmentIndex: Int) -> String {
        segmentIndex <= 1 ? "\(baseName).mp4" : "\(baseName) part\(segmentIndex).mp4"
    }

    static func availableURL(
        for proposedURL: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        guard fileExists(proposedURL) else { return proposedURL }
        let directory = proposedURL.deletingLastPathComponent()
        let ext = proposedURL.pathExtension
        let stem = proposedURL.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension(ext)
            if !fileExists(candidate) { return candidate }
            counter += 1
        }
    }
}
