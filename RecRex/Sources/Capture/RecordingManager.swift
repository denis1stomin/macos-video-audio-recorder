import AVFoundation
import ScreenCaptureKit

final class RecordingManager: NSObject, @unchecked Sendable {
    enum RecordingManagerError: Error {
        case noShareableContentFound
    }

    private let queue = DispatchQueue(label: "dev.denis1stomin.recrex.capture")

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var segmentStartWallClock = Date()
    private var segmentIndex = 1
    private var baseFileName = ""
    private var settings = RecordingSettings(videoSource: nil, captureSystemAudio: false, captureMicrophone: false)
    private var isPaused = false
    private var isRollingOverSegment = false
    private var savedFileURLs: [URL] = []

    /// Fires when ScreenCaptureKit stops the stream on its own (e.g. the captured window closed or its app quit).
    var onStreamStoppedUnexpectedly: (@Sendable (Error) -> Void)?

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func start(settings: RecordingSettings) async throws {
        self.settings = settings
        baseFileName = FileNaming.baseFileName(for: Date())
        segmentIndex = 1
        savedFileURLs = []
        queue.sync { try? beginSegmentWriter() }

        guard settings.needsScreenCaptureKit else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let filter: SCContentFilter
        switch settings.videoSource {
        case .window(let windowSource):
            filter = SCContentFilter(desktopIndependentWindow: windowSource.window)
        case .display(let displaySource):
            filter = SCContentFilter(display: displaySource.display, excludingApplications: [], exceptingWindows: [])
        case nil:
            guard let display = content.displays.first else {
                throw RecordingManagerError.noShareableContentFound
            }
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = settings.captureSystemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = settings.captureMicrophone
        config.showsCursor = true
        config.queueDepth = 8
        let (width, height) = videoDimensions()
        if settings.capturesVideo {
            config.width = width
            config.height = height
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        if settings.capturesVideo {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        }
        if settings.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if settings.captureMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func setPaused(_ paused: Bool) {
        queue.async { self.isPaused = paused }
    }

    func stop(discard: Bool = false) async -> [URL] {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        await finishCurrentSegment()
        let urls = queue.sync { savedFileURLs }
        guard !discard else {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            queue.sync { savedFileURLs = [] }
            return []
        }
        return urls
    }

    private func videoDimensions() -> (width: Int, height: Int) {
        switch settings.videoSource {
        case .display(let displaySource):
            return (displaySource.display.width * 2, displaySource.display.height * 2)
        case .window(let windowSource):
            return (Int(windowSource.window.frame.width) * 2, Int(windowSource.window.frame.height) * 2)
        case nil:
            return (1920, 1080)
        }
    }

    private nonisolated(unsafe) static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44_100,
        AVEncoderBitRateKey: 128_000,
    ]

    /// Must be called on `queue`.
    private func beginSegmentWriter() throws {
        let fileName = FileNaming.segmentFileName(baseName: baseFileName, segmentIndex: segmentIndex)
        let proposedURL = downloadsDirectory.appendingPathComponent(fileName)
        let url = FileNaming.availableURL(for: proposedURL)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        if settings.capturesVideo {
            let (width, height) = videoDimensions()
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            videoInput = input
        }

        if settings.captureSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            systemAudioInput = input
        }

        if settings.captureMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            microphoneInput = input
        }

        assetWriter = writer
        segmentStartWallClock = Date()
    }

    private func finishCurrentSegment() async {
        let writerToFinish: AVAssetWriter? = queue.sync {
            let writer = assetWriter
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
            assetWriter = nil
            videoInput = nil
            systemAudioInput = nil
            microphoneInput = nil
            return writer
        }
        guard let writerToFinish, writerToFinish.status == .writing else { return }
        await writerToFinish.finishWriting()
        queue.sync { savedFileURLs.append(writerToFinish.outputURL) }
    }

    /// Must be called on `queue`.
    private func rollOverToNextSegment() {
        guard !isRollingOverSegment else { return }
        isRollingOverSegment = true
        segmentIndex += 1
        Task {
            await finishCurrentSegment()
            queue.sync {
                try? beginSegmentWriter()
                isRollingOverSegment = false
            }
        }
    }
}

extension RecordingManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        queue.async { [self] in
            guard sampleBuffer.isValid, !isPaused, !isRollingOverSegment, let writer = assetWriter else { return }

            if writer.status == .unknown {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            }
            guard writer.status == .writing else { return }

            switch type {
            case .screen:
                if let videoInput, videoInput.isReadyForMoreMediaData {
                    videoInput.append(sampleBuffer)
                }
            case .audio:
                if let systemAudioInput, systemAudioInput.isReadyForMoreMediaData {
                    systemAudioInput.append(sampleBuffer)
                }
            case .microphone:
                if let microphoneInput, microphoneInput.isReadyForMoreMediaData {
                    microphoneInput.append(sampleBuffer)
                }
            @unknown default:
                break
            }

            if SegmentScheduler.shouldRollOver(segmentStart: segmentStartWallClock, now: Date()) {
                rollOverToNextSegment()
            }
        }
    }
}

extension RecordingManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStoppedUnexpectedly?(error)
    }
}
