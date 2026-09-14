enum StartButtonLabel {
    static func text(recordVideo: Bool) -> String {
        recordVideo ? "Select video source" : "Start recording only audio"
    }
}
