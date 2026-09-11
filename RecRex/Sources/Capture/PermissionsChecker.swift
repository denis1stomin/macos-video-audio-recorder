import AVFoundation
import ScreenCaptureKit

struct PermissionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum PermissionsChecker {
    static func missingPermissionAlert(for settings: RecordingSettings) async -> PermissionAlert? {
        if settings.needsScreenCaptureKit, !(await hasScreenRecordingAccess()) {
            return PermissionAlert(
                title: "Screen Recording access needed",
                message: "RecRex needs Screen Recording access to capture video or system audio. "
                    + "Open System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, "
                    + "enable RecRex, then try again."
            )
        }
        if settings.captureMicrophone, !hasMicrophoneAccess() {
            return PermissionAlert(
                title: "Microphone access needed",
                message: "RecRex needs Microphone access to record your voice. "
                    + "Open System Settings \u{2192} Privacy & Security \u{2192} Microphone, "
                    + "enable RecRex, then try again."
            )
        }
        return nil
    }

    private static func hasScreenRecordingAccess() async -> Bool {
        (try? await SCShareableContent.current) != nil
    }

    private static func hasMicrophoneAccess() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
