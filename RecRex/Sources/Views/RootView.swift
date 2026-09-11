import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            switch appState.stage {
            case .configuring:
                MainWindowView(appState: appState)
            case .selectingSource:
                SourceSelectionView(appState: appState)
            case .recording:
                ProcessingWindowView(appState: appState)
            }
        }
        .alert(item: $appState.permissionAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}
