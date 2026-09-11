import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("RecRex")
                .font(.largeTitle.bold())

            Text("Choose what to record.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Record video", isOn: $appState.recordVideo)
                Toggle("Record system audio", isOn: $appState.recordSystemAudio)
                Toggle("Record microphone", isOn: $appState.recordMicrophone)
            }
            .toggleStyle(.checkbox)

            Spacer()

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
                .disabled(appState.isLoadingSources || !appState.recordVideo && !appState.recordSystemAudio && !appState.recordMicrophone)
            }
        }
        .padding(24)
        .frame(width: 360, height: 280)
    }
}
