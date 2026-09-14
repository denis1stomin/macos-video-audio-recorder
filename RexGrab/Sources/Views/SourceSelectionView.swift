import ScreenCaptureKit
import SwiftUI

struct SourceSelectionView: View {
    enum Mode: Hashable {
        case wholeScreen
        case appWindow
    }

    @ObservedObject var appState: AppState
    @State private var mode: Mode = .wholeScreen
    // Remembers each tab's own last pick, so switching between "Whole screen" and "App window"
    // and back doesn't lose your selection on the tab you're leaving.
    @State private var selectedDisplay: DisplaySource?
    @State private var selectedWindow: WindowSource?

    init(appState: AppState) {
        self.appState = appState
        if case .display(let display) = appState.selectedSource {
            _selectedDisplay = State(initialValue: display)
        }
        // ScreenCaptureKit returns windows front-to-back, so after filtering out RexGrab's own
        // window this is simply "whatever window you were just looking at" — a much more
        // reliable default than guessing by app name or launch time.
        _selectedWindow = State(initialValue: appState.availableWindows.first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a video source")
                .font(.title.bold())

            Picker("", selection: $mode) {
                Text("Whole screen").tag(Mode.wholeScreen)
                Text("App window").tag(Mode.appWindow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .onChange(of: mode) { _, newMode in
                switch newMode {
                case .wholeScreen:
                    appState.selectedSource = selectedDisplay.map { .display($0) }
                case .appWindow:
                    appState.selectedSource = selectedWindow.map { .window($0) }
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 208), spacing: 16)], spacing: 16) {
                    switch mode {
                    case .wholeScreen:
                        ForEach(appState.availableDisplays) { display in
                            SourceThumbnailView(
                                title: display.resolutionText,
                                isSelected: appState.selectedSource == .display(display),
                                filter: SCContentFilter(display: display.display, excludingApplications: [], exceptingWindows: [])
                            ) {
                                selectedDisplay = display
                                appState.selectedSource = .display(display)
                            }
                        }
                    case .appWindow:
                        ForEach(appState.availableWindows) { window in
                            SourceThumbnailView(
                                title: window.displayName,
                                isSelected: appState.selectedSource == .window(window),
                                filter: SCContentFilter(desktopIndependentWindow: window.window)
                            ) {
                                selectedWindow = window
                                appState.selectedSource = .window(window)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 340)

            HStack {
                Button("Back") { appState.cancelSourceSelection() }
                    .controlSize(.large)
                Spacer()
                Button("Start Recording") {
                    Task { await appState.startRecording() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appState.selectedSource == nil)
            }
        }
        .padding(24)
        .frame(width: RexGrabWindowSize.width, height: 500)
        .dinoThemedBackground()
    }
}

private struct SourceThumbnailView: View {
    let title: String
    let isSelected: Bool
    let filter: SCContentFilter
    let action: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView()
                }
            }
            .frame(height: 143)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(title)
                .font(.footnote)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let config = SCStreamConfiguration()
        config.width = 416
        config.height = 260
        config.showsCursor = false
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return
        }
        thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
