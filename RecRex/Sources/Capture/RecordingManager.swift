import AVFoundation
import os
import ScreenCaptureKit

final class RecordingManager: NSObject, @unchecked Sendable {
    enum RecordingManagerError: Error {
        case noShareableContentFound
    }

    private let logger = Logger(subsystem: "dev.denis1stomin.recrex", category: "capture")
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
    private var hasLoggedFirstSample: [SCStreamOutputType: Bool] = [:]
    private var hasLoggedNotReady: [SCStreamOutputType: Bool] = [:]
    /// Where the current segment should end up once finished (in Downloads). We write to a
    /// private temporary location first and move it there on completion — see beginSegmentWriter().
    private var currentFinalURL: URL?

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
        logger.notice("Stream started: video=\(settings.capturesVideo) systemAudio=\(settings.captureSystemAudio) mic=\(settings.captureMicrophone) size=\(width)x\(height)")
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
        let finalURL = FileNaming.availableURL(for: proposedURL)

        // Write into our own container's temporary directory first, then move the finished file
        // into Downloads once writing completes. Writing an AVAssetWriter's continuous stream
        // directly into the sandbox-redirected Downloads path has been observed to fail
        // immediately (AVFoundationErrorDomain -11800 / NSOSStatusErrorDomain -16122); a single
        // post-hoc move via the com.apple.security.files.downloads.read-write entitlement does
        // not hit that failure.
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)

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
        currentFinalURL = finalURL
        segmentStartWallClock = Date()
        logger.notice("Segment writer created at \(tempURL.path, privacy: .public), will move to \(finalURL.path, privacy: .public)")
    }

    private func finishCurrentSegment() async {
        let writerToFinish: AVAssetWriter?
        let finalURL: URL?
        (writerToFinish, finalURL) = queue.sync {
            let writer = assetWriter
            let url = currentFinalURL
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()
            assetWriter = nil
            currentFinalURL = nil
            videoInput = nil
            systemAudioInput = nil
            microphoneInput = nil
            return (writer, url)
        }
        guard let writerToFinish else { return }
        guard writerToFinish.status == .writing else {
            // The writer never received a sample (e.g. stopped immediately, or capture never
            // started) — AVAssetWriter already created an empty placeholder file at init time,
            // so clean it up instead of leaving 0-byte junk behind.
            logger.error("Writer never reached .writing (status=\(writerToFinish.status.rawValue), error=\(String(describing: writerToFinish.error), privacy: .public)) — removing empty file")
            try? FileManager.default.removeItem(at: writerToFinish.outputURL)
            return
        }
        await writerToFinish.finishWriting()
        logger.notice("Finished writing \(writerToFinish.outputURL.lastPathComponent, privacy: .public) — finalStatus=\(writerToFinish.status.rawValue) error=\(String(describing: writerToFinish.error), privacy: .public)")

        guard writerToFinish.status == .completed, let finalURL else {
            return
        }
        do {
            try FileManager.default.moveItem(at: writerToFinish.outputURL, to: finalURL)
            logger.notice("Moved segment to \(finalURL.path, privacy: .public)")
            queue.sync { savedFileURLs.append(finalURL) }
        } catch {
            logger.error("Failed to move segment to Downloads: \(String(describing: error), privacy: .public)")
            // Better to surface the file at its temp location than to lose it silently.
            queue.sync { savedFileURLs.append(writerToFinish.outputURL) }
        }
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

private func isCompleteVideoFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
    guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
        let attachments = attachmentsArray.first,
        let statusRawValue = attachments[.status] as? Int,
        let status = SCFrameStatus(rawValue: statusRawValue) else {
        return false
    }
    return status == .complete
}

extension RecordingManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        queue.async { [self] in
            guard sampleBuffer.isValid else {
                logger.error("Dropping invalid sample buffer of type \(String(describing: type), privacy: .public)")
                return
            }
            guard !isPaused, !isRollingOverSegment else { return }
            guard let writer = assetWriter else {
                logger.error("Dropping sample of type \(String(describing: type), privacy: .public) — no assetWriter")
                return
            }

            if hasLoggedFirstSample[type] != true {
                hasLoggedFirstSample[type] = true
                logger.notice("First sample received for type \(String(describing: type), privacy: .public), writer.status=\(writer.status.rawValue)")
            }

            if writer.status == .unknown {
                guard writer.startWriting() else {
                    logger.error("startWriting() failed: \(String(describing: writer.error), privacy: .public)")
                    return
                }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                logger.notice("Started writer session at \(sampleBuffer.presentationTimeStamp.seconds)")
            }
            guard writer.status == .writing else {
                if hasLoggedNotReady[type] != true {
                    hasLoggedNotReady[type] = true
                    logger.error("Writer not in .writing status (\(writer.status.rawValue)), error=\(String(describing: writer.error), privacy: .public)")
                }
                return
            }

            switch type {
            case .screen:
                // ScreenCaptureKit also delivers periodic non-content "status" frames (idle,
                // started, stopped, suspended, blank) that pass `sampleBuffer.isValid` but have
                // no real pixel data — feeding one into the H.264 hardware encoder can fail the
                // whole writer with an opaque VideoToolbox error. Only encode .complete frames.
                guard isCompleteVideoFrame(sampleBuffer) else { return }
                if let videoInput, videoInput.isReadyForMoreMediaData {
                    videoInput.append(sampleBuffer)
                } else if hasLoggedNotReady[type] != true {
                    hasLoggedNotReady[type] = true
                    logger.error("videoInput not ready for more data (input=\(self.videoInput != nil))")
                }
            case .audio:
                if let systemAudioInput, systemAudioInput.isReadyForMoreMediaData {
                    systemAudioInput.append(sampleBuffer)
                } else if hasLoggedNotReady[type] != true {
                    hasLoggedNotReady[type] = true
                    logger.error("systemAudioInput not ready for more data (input=\(self.systemAudioInput != nil))")
                }
            case .microphone:
                if let microphoneInput, microphoneInput.isReadyForMoreMediaData {
                    microphoneInput.append(sampleBuffer)
                } else if hasLoggedNotReady[type] != true {
                    hasLoggedNotReady[type] = true
                    logger.error("microphoneInput not ready for more data (input=\(self.microphoneInput != nil))")
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
        logger.error("Stream stopped with error: \(String(describing: error), privacy: .public)")
        onStreamStoppedUnexpectedly?(error)
    }
}
