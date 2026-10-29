import AVFoundation
import CoreImage

/// 实况照片 + 摄影风格：把实况的动态部分（.mov）逐帧套用与静态图相同的风格，
/// 并保留内容标识（content identifier）、静态帧时间等元数据，相册才会把它当成实况照片。
/// 任何一步失败都返回 nil，调用方会退回“保留原始动态”。
enum LivePhotoStyler {
    static func style(movie sourceURL: URL, snapshot: FilterEngine.Snapshot, context: CIContext) -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YCam-LiveStyled-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else { return nil }
        writer.metadata = asset.metadata

        // 视频：解码成 BGRA → 套风格 → 重新编码（保持原来的旋转信息）
        let width = Int(videoTrack.naturalSize.width)
        let height = Int(videoTrack.naturalSize.height)
        guard width > 0, height > 0 else { return nil }
        let readerVideo = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        guard reader.canAdd(readerVideo) else { return nil }
        reader.add(readerVideo)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, width * height * 5),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerVideo = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideo.transform = videoTrack.preferredTransform
        writerVideo.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerVideo, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(writerVideo) else { return nil }
        writer.add(writerVideo)

        // 音频与元数据轨道（含“静态帧时间”）：原样复制
        var copyPairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for track in asset.tracks(withMediaType: .audio) + asset.tracks(withMediaType: .metadata) {
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            var hint: CMFormatDescription?
            if let first = track.formatDescriptions.first {
                hint = (first as! CMFormatDescription)
            }
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: hint)
            if reader.canAdd(readerOutput), writer.canAdd(input) {
                reader.add(readerOutput)
                writer.add(input)
                copyPairs.append((readerOutput, input))
            }
        }

        guard reader.startReading() else { return nil }
        guard writer.startWriting() else {
            reader.cancelReading()
            return nil
        }
        writer.startSession(atSourceTime: videoTrack.timeRange.start)

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "ycam.live.style")
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

        group.enter()
        writerVideo.requestMediaDataWhenReady(on: queue) {
            while writerVideo.isReadyForMoreMediaData {
                guard let sample = readerVideo.copyNextSampleBuffer() else {
                    writerVideo.markAsFinished()
                    group.leave()
                    return
                }
                autoreleasepool {
                    guard let source = CMSampleBufferGetImageBuffer(sample), let pool = adaptor.pixelBufferPool else { return }
                    var target: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess, let output = target else { return }
                    let image = CIImage(cvPixelBuffer: source)
                    let styled = FilterEngine.shared.process(image, snapshot: snapshot, grainScale: 1)
                    context.render(styled, to: output, bounds: image.extent, colorSpace: colorSpace)
                    _ = adaptor.append(output, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
                }
            }
        }

        for pair in copyPairs {
            let readerOutput = pair.0
            let input = pair.1
            group.enter()
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = readerOutput.copyNextSampleBuffer(), input.append(sample) else {
                        input.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        if group.wait(timeout: .now() + 40) == .timedOut {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        guard reader.status != .failed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + 40)
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return outputURL
    }
}
