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

            GroupBox("Choose what to record") {
                VStack(alignment: .leading, spacing: 14) {
                    RecordingOptionRow(title: "Record video", isOn: $appState.recordVideo)
                    RecordingOptionRow(title: "Record system audio", isOn: $appState.recordSystemAudio)
                    RecordingOptionRow(title: "Record microphone", isOn: $appState.recordMicrophone)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)

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
                .controlSize(.large)
                .disabled(appState.isLoadingSources || !appState.recordVideo && !appState.recordSystemAudio && !appState.recordMicrophone)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: RecRexWindowSize.width)
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
