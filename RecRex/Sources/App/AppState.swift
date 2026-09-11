import AppKit
import ScreenCaptureKit
import SwiftUI

enum AppStage: Equatable {
    case configuring
    case selectingSource
    case recording
}

@MainActor
final class AppState: ObservableObject {
    @Published var recordVideo = true
    @Published var recordSystemAudio = true
    @Published var recordMicrophone = false

    @Published private(set) var stage: AppStage = .configuring
    @Published private(set) var isPaused = false
    @Published private(set) var recordingStartDate: Date?
    @Published private(set) var isLoadingSources = false
    @Published private(set) var availableDisplays: [DisplaySource] = []
    @Published private(set) var availableWindows: [WindowSource] = []
    @Published var selectedSource: VideoSource?
    @Published var permissionAlert: PermissionAlert?

    private let recordingManager = RecordingManager()
    private var pausedIntervalTotal: TimeInterval = 0
    private var currentPauseStart: Date?

    var startButtonLabel: String { StartButtonLabel.text(recordVideo: recordVideo) }

    var currentSettings: RecordingSettings {
        RecordingSettings(
            videoSource: recordVideo ? selectedSource : nil,
            captureSystemAudio: recordSystemAudio,
            captureMicrophone: recordMicrophone
        )
    }

    func primaryButtonTapped() {
        if recordVideo {
            Task { await beginSourceSelection() }
        } else {
            Task { await startRecording() }
        }
    }

    func beginSourceSelection() async {
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier
            availableDisplays = content.displays.map(DisplaySource.init)
            availableWindows = content.windows
                .filter { ($0.title?.isEmpty == false) }
                .filter { $0.owningApplication?.bundleIdentifier != ownBundleID }
                .map(WindowSource.init)
            stage = .selectingSource
        } catch {
            permissionAlert = PermissionAlert(
                title: "Screen Recording access needed",
                message: "RecRex needs Screen Recording access to list screens and windows. "
                    + "Open System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, "
                    + "enable RecRex, then try again."
            )
        }
    }

    func cancelSourceSelection() {
        selectedSource = nil
        availableDisplays = []
        availableWindows = []
        stage = .configuring
    }

    func startRecording() async {
        let settings = currentSettings
        if let alert = await PermissionsChecker.missingPermissionAlert(for: settings) {
            permissionAlert = alert
            return
        }
        recordingManager.onStreamStoppedUnexpectedly = { [weak self] _ in
            Task { @MainActor in
                await self?.stopRecording()
            }
        }
        do {
            try await recordingManager.start(settings: settings)
            recordingStartDate = Date()
            isPaused = false
            stage = .recording
        } catch {
            permissionAlert = PermissionAlert(
                title: "Couldn't start recording",
                message: error.localizedDescription
            )
        }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            currentPauseStart = Date()
        } else if let pauseStart = currentPauseStart {
            pausedIntervalTotal += Date().timeIntervalSince(pauseStart)
            currentPauseStart = nil
        }
        recordingManager.setPaused(isPaused)
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let start = recordingStartDate else { return 0 }
        let pausedSoFar = pausedIntervalTotal + (isPaused ? now.timeIntervalSince(currentPauseStart ?? now) : 0)
        return now.timeIntervalSince(start) - pausedSoFar
    }

    func stopRecording() async {
        let savedFiles = await recordingManager.stop()
        revealInFinder(savedFiles)
        reset()
    }

    func discardRecording() async {
        _ = await recordingManager.stop(discard: true)
        reset()
    }

    private func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            NSWorkspace.shared.open(downloads)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func reset() {
        stage = .configuring
        isPaused = false
        recordingStartDate = nil
        pausedIntervalTotal = 0
        currentPauseStart = nil
        selectedSource = nil
        availableDisplays = []
        availableWindows = []
    }
}
