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
                message: "RexGrab needs Screen Recording access to capture video or system audio. "
                    + "Open System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, "
                    + "enable RexGrab, then try again."
            )
        }
        if settings.captureMicrophone, !(await hasMicrophoneAccess()) {
            return PermissionAlert(
                title: "Microphone access needed",
                message: "RexGrab needs Microphone access to record your voice. "
                    + "Open System Settings \u{2192} Privacy & Security \u{2192} Microphone, "
                    + "enable RexGrab, then try again."
            )
        }
        return nil
    }

    private static func hasScreenRecordingAccess() async -> Bool {
        (try? await SCShareableContent.current) != nil
    }

    private static func hasMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
