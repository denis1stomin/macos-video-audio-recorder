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
    /// The exact pixel dimensions to encode video at: derived from the SCContentFilter's own
    /// contentRect + pointPixelScale once it's built (see start()) — using the filter's actual
    /// content size instead of guessing (e.g. assuming a fixed Retina 2x scale) is what keeps the
    /// encoded aspect ratio matching a window's real shape, with no black letterboxing — and then
    /// capped to maxVideoDimension on the longer edge (a meeting recording doesn't need native 5K/6K
    /// pixels; ScreenCaptureKit itself does the downscaling via SCStreamConfiguration.width/height,
    /// so this never costs an extra resample pass).
    private(set) var videoPixelSize: (width: Int, height: Int) = (1920, 1080)
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

        guard settings.needsScreenCaptureKit else {
            queue.sync { try? beginSegmentWriter() }
            return
        }

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

        if settings.capturesVideo {
            let scale = CGFloat(filter.pointPixelScale)
            videoPixelSize = Self.downscaledIfNeeded(
                width: Self.evenPixelDimension(filter.contentRect.width * scale),
                height: Self.evenPixelDimension(filter.contentRect.height * scale)
            )
        }
        // The writer/encoder is set up only now, after videoPixelSize reflects the filter's real
        // content size — beginSegmentWriter() (and any later rollover) reads that stored value.
        queue.sync { try? beginSegmentWriter() }

        let config = SCStreamConfiguration()
        config.capturesAudio = settings.captureSystemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = settings.captureMicrophone
        config.showsCursor = true
        config.queueDepth = 8
        if settings.capturesVideo {
            config.width = videoPixelSize.width
            config.height = videoPixelSize.height
            // ScreenCaptureKit otherwise delivers frames at the display's own refresh rate (up to
            // 120Hz on ProMotion) regardless of on-screen motion — capping it is one of the two
            // main levers (with the explicit video bitrate below) for keeping long meeting
            // recordings from ballooning in size; a talking-head screen share doesn't need more.
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(Self.videoFrameRate))
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
        logger.notice("Stream started: video=\(settings.capturesVideo) systemAudio=\(settings.captureSystemAudio) mic=\(settings.captureMicrophone) size=\(self.videoPixelSize.width)x\(self.videoPixelSize.height)")
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

    /// H.264 (with standard 4:2:0 chroma subsampling) requires even width/height, but a content
    /// rect in points scaled by pointPixelScale can land on an odd pixel count — round to the
    /// nearest even number rather than plain-rounding, so the encoder never has to pad itself.
    private static func evenPixelDimension(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    private static let videoFrameRate: Double = 30

    /// A meeting recording doesn't need native 5K/6K pixels — cap the longer edge and scale the
    /// other proportionally so aspect ratio (and therefore no letterboxing) is preserved.
    private static let maxVideoDimension = 1080

    private static func downscaledIfNeeded(width: Int, height: Int) -> (width: Int, height: Int) {
        let longestEdge = max(width, height)
        guard longestEdge > maxVideoDimension else { return (width, height) }
        let scale = CGFloat(maxVideoDimension) / CGFloat(longestEdge)
        return (
            evenPixelDimension(CGFloat(width) * scale),
            evenPixelDimension(CGFloat(height) * scale)
        )
    }

    /// A rough screen-content H.264 target (bits per pixel per frame) — enough to keep UI text
    /// legible without VideoToolbox's own uncapped default (observed to produce ~2.4 GB for a
    /// 70-minute full-screen recording, before this and the resolution/frame-rate caps above)
    /// growing unbounded on a high-resolution display. Clamped so a tiny recorded window doesn't
    /// starve for bits and a max-size capture doesn't run away either.
    private static func averageVideoBitRate(width: Int, height: Int) -> Int {
        let bitsPerPixelPerFrame = 0.06
        let raw = Double(width * height) * videoFrameRate * bitsPerPixelPerFrame
        return min(max(Int(raw.rounded()), 1_500_000), 8_000_000)
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
            let (width, height) = videoPixelSize
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Self.averageVideoBitRate(width: width, height: height),
                    AVVideoExpectedSourceFrameRateKey: Int(Self.videoFrameRate),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
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
