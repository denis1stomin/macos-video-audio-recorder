import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                DinoBadge()
                Text("RecRex")
                    .font(.largeTitle.bold())
            }

            Text("Choose what to record.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                RecordingOptionRow(title: "Record video", isOn: $appState.recordVideo)
                RecordingOptionRow(title: "Record system audio", isOn: $appState.recordSystemAudio)
                RecordingOptionRow(title: "Record microphone", isOn: $appState.recordMicrophone)
            }

            HStack {
                Spacer()
                Button {
                    appState.primaryButtonTapped()
                } label: {
                    if appState.isLoadingSources {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(appState.startButtonLabel)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoadingSources || !appState.recordVideo && !appState.recordSystemAudio && !appState.recordMicrophone)
            }
        }
        .padding(24)
        .frame(width: 360)
        .dinoThemedBackground()
    }
}

/// A toggle row with the switch on the left and its caption reading to the right of it.
private struct RecordingOptionRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
            Text(title)
        }
    }
}
