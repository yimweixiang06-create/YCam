import AVFoundation

/// 把“已套用风格”的画面写成 .mov，所以录出来的视频与取景器里看到的一致。
/// 注意：所有方法都必须在同一条串行队列（CameraModel.dataQueue，也就是摄像头 / 麦克风回调所在队列）上调用，
/// 因此内部不需要加锁。
final class VideoRecorder {
    enum RecorderError: LocalizedError {
        case tooShort
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .tooShort: return "录制时间太短，没有写入任何画面"
            case .writer(let message): return message
            }
        }
    }

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var audioSettings: [String: Any]?
    private var armed = false
    private var sessionStart: CMTime?
    private var lastVideoPTS = CMTime.invalid
    private var videoFrames = 0
    private var failure: Error?

    /// 进入“等待第一帧”状态；真正创建 writer 发生在第一帧到达时（这样能拿到真实分辨率）。
    func arm(url: URL, audioSettings: [String: Any]?) {
        reset()
        outputURL = url
        self.audioSettings = audioSettings
        armed = true
    }

    func appendVideo(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard armed else { return }
        if writer == nil {
            guard setupWriter(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)) else {
                armed = false
                return
            }
        }
        guard let writer, let videoInput, let adaptor, writer.status == .writing else {
            if let writer, writer.status == .failed {
                failure = writer.error ?? RecorderError.writer("视频写入器失败")
                armed = false
            }
            return
        }
        if sessionStart == nil {
            writer.startSession(atSourceTime: pts)
            sessionStart = pts
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        if lastVideoPTS.isValid, CMTimeCompare(pts, lastVideoPTS) <= 0 { return }
        if adaptor.append(pixelBuffer, withPresentationTime: pts) {
            lastVideoPTS = pts
            videoFrames += 1
        } else {
            failure = writer.error ?? RecorderError.writer("写入视频帧失败")
            armed = false
        }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        guard armed, let start = sessionStart, let audioInput, let writer,
              writer.status == .writing, audioInput.isReadyForMoreMediaData else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if CMTimeCompare(pts, start) < 0 { return }
        if !audioInput.append(sample) {
            // 音频写入失败不影响画面：放弃音轨，保留视频。
            audioInput.markAsFinished()
            self.audioInput = nil
        }
    }

    /// 结束录制。completion 可能在任意线程被调用。
    func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
        armed = false
        guard let writer, let url = outputURL else {
            let error = failure ?? RecorderError.tooShort
            reset()
            completion(.failure(error))
            return
        }
        if let failure {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            reset()
            completion(.failure(failure))
            return
        }
        guard videoFrames > 0, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            reset()
            completion(.failure(RecorderError.tooShort))
            return
        }
        if lastVideoPTS.isValid { writer.endSession(atSourceTime: lastVideoPTS) }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        reset()
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(url))
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? RecorderError.writer("视频写入失败")))
            }
        }
    }

    // MARK: - Private

    private func setupWriter(width: Int, height: Int) -> Bool {
        guard let url = outputURL else { return false }
        try? FileManager.default.removeItem(at: url)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

            let bitrate = Int(Double(width * height) * 30.0 * 0.25)   // 1080p30 ≈ 15 Mbps
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            guard writer.canAdd(videoInput) else {
                failure = RecorderError.writer("无法创建视频轨道")
                return false
            }
            writer.add(videoInput)

            if let audioSettings {
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    self.audioInput = audioInput
                }
            }

            guard writer.startWriting() else {
                failure = writer.error ?? RecorderError.writer("无法开始写入视频")
                return false
            }
            self.writer = writer
            self.videoInput = videoInput
            self.adaptor = adaptor
            return true
        } catch {
            failure = error
            return false
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        outputURL = nil
        audioSettings = nil
        armed = false
        sessionStart = nil
        lastVideoPTS = .invalid
        videoFrames = 0
        failure = nil
    }
}
