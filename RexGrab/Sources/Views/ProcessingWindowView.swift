import SwiftUI

struct ProcessingWindowView: View {
    @ObservedObject var appState: AppState
    @State private var now = Date()
    @State private var showingDiscardConfirmation = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Text("Recording")
                .font(.largeTitle.bold())

            Text(descriptionText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(elapsedString)
                .font(.system(size: 48, weight: .medium, design: .monospaced))

            if appState.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                HStack(spacing: 16) {
                    Button(appState.isPaused ? "Resume" : "Pause") {
                        appState.togglePause()
                    }
                    .controlSize(.large)
                    Button("Stop and Save") {
                        Task { await appState.stopRecording() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()

                Button("Discard") {
                    showingDiscardConfirmation = true
                }
                .controlSize(.large)
                .foregroundStyle(.red)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: RexGrabWindowSize.width)
        .dinoThemedBackground()
        .onReceive(timer) { now = $0 }
        .confirmationDialog(
            "Discard this recording?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Recording", role: .destructive) {
                Task { await appState.discardRecording() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. The recording won't be saved.")
        }
    }

    private var descriptionText: String {
        var parts: [String] = []
        if appState.currentSettings.capturesVideo { parts.append("video") }
        if appState.recordSystemAudio { parts.append("system audio") }
        if appState.recordMicrophone { parts.append("microphone") }
        return "Recording " + parts.joined(separator: ", ")
    }

    private var elapsedString: String {
        let interval = max(0, Int(appState.elapsed(at: now)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
