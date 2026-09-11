import ScreenCaptureKit

struct DisplaySource: Identifiable, Hashable, @unchecked Sendable {
    let display: SCDisplay

    var id: CGDirectDisplayID { display.displayID }

    var resolutionText: String { "Display \(display.width) × \(display.height)" }

    static func == (lhs: DisplaySource, rhs: DisplaySource) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct WindowSource: Identifiable, Hashable, @unchecked Sendable {
    let window: SCWindow

    var id: CGWindowID { window.windowID }

    var displayName: String {
        window.title?.isEmpty == false
            ? window.title!
            : (window.owningApplication?.applicationName ?? "Untitled window")
    }

    static func == (lhs: WindowSource, rhs: WindowSource) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum VideoSource: Equatable {
    case display(DisplaySource)
    case window(WindowSource)
}

struct RecordingSettings {
    var videoSource: VideoSource?
    var captureSystemAudio: Bool
    var captureMicrophone: Bool

    var capturesVideo: Bool { videoSource != nil }
    var needsScreenCaptureKit: Bool { capturesVideo || captureSystemAudio }
}
