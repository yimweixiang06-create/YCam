import AVFoundation
import Photos
import SwiftUI
import UIKit
import CoreImage
import ImageIO

// MARK: - Shared types

enum CaptureMode: String, CaseIterable, Identifiable {
    case video = "视频"
    case photo = "照片"
    var id: String { rawValue }
}

enum PermissionState {
    case unknown, granted, denied
}

enum CameraError: LocalizedError {
    case notReady
    case photosDenied
    case capture(String)
    case save(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "相机尚未就绪，请稍候再试"
        case .photosDenied: return "没有“添加到照片”的权限，无法保存。请到 设置 → YCam → 照片 中允许。"
        case .capture(let message): return "拍照失败：\(message)"
        case .save(let message): return "保存失败：\(message)"
        }
    }
}

/// 一次拍照任务（按下快门瞬间的风格状态在这里固定下来）。
private final class PhotoJob {
    let settings: StyleSettings
    let requestedLiveURL: URL?
    let cropAspect: CGFloat?       // 取景器全屏时：按屏幕宽高比居中裁剪成片
    var data: Data?
    var producedLiveURL: URL?
    var error: Error?

    init(settings: StyleSettings, requestedLiveURL: URL?, cropAspect: CGFloat?) {
        self.settings = settings
        self.requestedLiveURL = requestedLiveURL
        self.cropAspect = cropAspect
    }
}

// MARK: - CameraModel

final class CameraModel: NSObject, ObservableObject {

    // MARK: Published UI state（只在主线程修改）

    @Published private(set) var permission: PermissionState = .unknown
    @Published private(set) var cameraReady = false
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var flashAvailable = false
    @Published var flashEnabled = false
    @Published private(set) var livePhotoSupported = false
    @Published var livePhotoEnabled = true
    @Published private(set) var micAvailable = false
    @Published private(set) var isCapturingPhoto = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizingVideo = false
    @Published private(set) var recordingStart: Date?
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var shutterPulse = 0
    @Published var message: String?

    /// 唯一的风格状态：名称 / 圆点 / 预览 / 照片 / 视频都读取它。
    @Published var styleSettings = StyleSettings() {
        didSet { FilterEngine.shared.update(styleSettings) }
    }

    // MARK: Private state

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "ycam.session")
    private let dataQueue = DispatchQueue(label: "ycam.data", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "ycam.processing", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?                          // sessionQueue
    private var audioInput: AVCaptureDeviceInput?                          // sessionQueue
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?  // sessionQueue
    private var isConfigured = false                                       // sessionQueue
    private var isStarting = false                                         // 主线程
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let recorder = VideoRecorder()                                 // 仅 dataQueue
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var pixelPool: CVPixelBufferPool?                              // 仅 dataQueue
    private var pixelPoolSize = (width: 0, height: 0)                      // 仅 dataQueue
    private var currentJob: PhotoJob?
    private let jobLock = NSLock()
    private var observers: [NSObjectProtocol] = []
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Lifecycle

    override init() {
        super.init()
        FilterEngine.shared.update(styleSettings)
        registerSessionObservers()
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }

    func attach(displayLayer layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
    }

    /// 请求权限并启动相机。可重复调用（回到前台、从设置返回时都会再次调用）。
    @MainActor
    func requestAndStart() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let cameraGranted = await authorize(.video)
        permission = cameraGranted ? .granted : .denied
        guard cameraGranted else { return }

        // 麦克风 / 照片权限被拒绝不会阻止取景，只会让对应功能给出明确提示。
        let micGranted = await authorize(.audio)
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        sessionQueue.async { self.configureAndRun(withAudio: micGranted) }
    }

    func sceneWillResignActive() {
        if isRecording { stopRecording() }
    }

    private func authorize(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }

    private func photosAddAllowed() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }

    private func post(_ text: String) {
        DispatchQueue.main.async { self.message = text }
    }

    private func registerSessionObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.isRecording { self.stopRecording() }
            self.message = "相机发生错误，正在尝试恢复"
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning { self.session.startRunning() }
            }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.isRecording { self.stopRecording() }
            self.message = "相机被系统暂时占用（如来电或多任务）"
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning { self.session.startRunning() }
            }
        })
    }

    // MARK: Session configuration（sessionQueue）

    private static func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func configureAndRun(withAudio: Bool) {
        if !isConfigured {
            guard configureSession() else { return }
            isConfigured = true
        }
        if withAudio { addAudioIfNeeded() }
        if !session.isRunning { session.startRunning() }
        publishCapabilities()
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.cameraDevice(position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            post("无法使用相机（设备不支持或被其他 App 占用）")
            return false
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            post("无法创建拍照输出")
            return false
        }
        session.addOutput(photoOutput)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            post("无法创建实时画面输出")
            return false
        }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        applyConnectionSettings()
        if photoOutput.isLivePhotoCaptureSupported {
            photoOutput.isLivePhotoCaptureEnabled = true
        }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return true
    }

    private func addAudioIfNeeded() {
        guard audioInput == nil,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        audioOutput.setSampleBufferDelegate(self, queue: dataQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            audioInput = input
        } else {
            session.removeInput(input)
        }
    }

    /// 实时画面 / 照片统一竖向输出；前置镜头的取景镜像交给显示层处理，成片不镜像。
    private func applyConnectionSettings() {
        let outputs: [AVCaptureOutput] = [videoOutput, photoOutput]
        for output in outputs {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    private func publishCapabilities() {
        let device = videoInput?.device
        let flash = (device?.hasFlash ?? false) || (device?.hasTorch ?? false)
        let live = photoOutput.isLivePhotoCaptureSupported
        let devicePosition = device?.position ?? .back
        let running = session.isRunning
        let mic = audioInput != nil
        DispatchQueue.main.async {
            self.flashAvailable = flash
            if !flash { self.flashEnabled = false }
            self.livePhotoSupported = live
            self.position = devicePosition
            self.micAvailable = mic
            self.cameraReady = running
        }
    }

    // MARK: Mode / flash / flip

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode else { return }
        guard !isRecording, !isCapturingPhoto, !isFinalizingVideo else { return }
        mode = newMode
        let wantTorch = newMode == .video && flashEnabled
        sessionQueue.async {
            self.applyPreset(for: newMode)
            self.setTorch(wantTorch)
            self.publishCapabilities()
        }
    }

    private func applyPreset(for mode: CaptureMode) {
        guard isConfigured else { return }
        session.beginConfiguration()
        switch mode {
        case .photo:
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        case .video:
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
        }
        session.commitConfiguration()
        applyConnectionSettings()
    }

    /// 视频模式下“闪光灯”= 手电筒；照片模式下在拍照时真正触发闪光灯硬件。
    func toggleFlash() {
        guard flashAvailable else {
            message = "当前镜头不支持闪光灯"
            return
        }
        flashEnabled.toggle()
        let wantTorch = flashEnabled && mode == .video
        sessionQueue.async { self.setTorch(wantTorch) }
    }

    private func setTorch(_ on: Bool) {   // sessionQueue
        guard let device = videoInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchAvailable, device.isTorchModeSupported(.on) {
                device.torchMode = .on
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            post("手电筒无法切换：\(error.localizedDescription)")
        }
    }

    func flipCamera() {
        guard cameraReady, !isRecording, !isCapturingPhoto, !isFinalizingVideo else { return }
        let target: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async {
            guard self.isConfigured, let current = self.videoInput,
                  let device = Self.cameraDevice(position: target),
                  let next = try? AVCaptureDeviceInput(device: device) else {
                self.post("无法切换镜头")
                return
            }
            self.setTorch(false)
            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(next) {
                self.session.addInput(next)
                self.videoInput = next
            } else {
                self.session.addInput(current)
                self.session.commitConfiguration()
                self.post("无法切换镜头")
                return
            }
            self.session.commitConfiguration()
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            self.applyConnectionSettings()
            self.publishCapabilities()
            DispatchQueue.main.async {
                if self.mode == .video, self.flashEnabled, device.hasTorch {
                    self.sessionQueue.async { self.setTorch(true) }
                }
            }
        }
    }

    func openPhotos() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Photo capture

    func capturePhoto(cropAspect: CGFloat? = nil) {
        guard mode == .photo else { return }
        guard cameraReady else { message = CameraError.notReady.localizedDescription; return }
        guard !isCapturingPhoto, !isRecording, !isFinalizingVideo else { return }
        guard photosAddAllowed() else { message = CameraError.photosDenied.localizedDescription; return }

        let style = styleSettings                    // 按下快门这一刻的风格状态
        let wantFlash = flashEnabled
        let wantLive = livePhotoEnabled && style.isIdentity && cropAspect == nil   // 处理过（风格 / 裁剪）的静态图不能与原始实况视频配对
        isCapturingPhoto = true

        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            if wantFlash, let device = self.videoInput?.device, device.hasFlash,
               self.photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = .on
            }
            var liveURL: URL?
            if wantLive, self.photoOutput.isLivePhotoCaptureSupported, self.photoOutput.isLivePhotoCaptureEnabled {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("YCam-Live-\(UUID().uuidString).mov")
                settings.livePhotoMovieFileURL = url
                liveURL = url
            }
            if let connection = self.photoOutput.connection(with: .video),
               let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            self.setJob(PhotoJob(settings: style, requestedLiveURL: liveURL, cropAspect: cropAspect))
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func setJob(_ job: PhotoJob?) {
        jobLock.lock()
        currentJob = job
        jobLock.unlock()
    }

    private func activeJob() -> PhotoJob? {
        jobLock.lock()
        defer { jobLock.unlock() }
        return currentJob
    }

    private func discardLiveMovie(_ job: PhotoJob) {
        if let url = job.producedLiveURL { try? FileManager.default.removeItem(at: url) }
        if let url = job.requestedLiveURL { try? FileManager.default.removeItem(at: url) }
    }

    private func photoFailed(_ error: Error) {
        setJob(nil)
        DispatchQueue.main.async {
            self.isCapturingPhoto = false
            self.message = error.localizedDescription
        }
    }

    private func photoSucceeded(text: String, thumbnail: UIImage?) {
        setJob(nil)
        DispatchQueue.main.async {
            self.isCapturingPhoto = false
            if let thumbnail { self.lastThumbnail = thumbnail }
            self.message = text
        }
    }

    /// 在后台线程完成：风格处理 → 写入相册。
    private func finishPhoto(_ job: PhotoJob, data: Data) {
        var output = data
        var keepLive = false
        var notice: String?

        let needsProcessing = !job.settings.isIdentity || job.cropAspect != nil
        if !needsProcessing {
            keepLive = job.producedLiveURL != nil
        } else {
            discardLiveMovie(job)
            if let processed = renderFiltered(data, settings: job.settings, cropAspect: job.cropAspect) {
                output = processed
            } else {
                notice = "处理失败，已保存未处理的原图"
            }
        }
        let thumbnail = Self.makeThumbnail(from: output)
        let producedLive = job.producedLiveURL
        let finalNotice = notice
        let finalKeepLive = keepLive
        let finalData = output

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: .photo, data: finalData, options: options)
            if finalKeepLive, let movie = producedLive {
                let movieOptions = PHAssetResourceCreationOptions()
                movieOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: movie, options: movieOptions)
            }
        }) { success, error in
            self.discardLiveMovie(job)
            if success {
                let suffix = job.settings.isIdentity ? "" : "（已应用：\(job.settings.style.title)）"
                let text = finalNotice ?? (finalKeepLive ? "实况照片已保存到照片图库" : "照片已保存到照片图库\(suffix)")
                self.photoSucceeded(text: text, thumbnail: thumbnail)
            } else {
                self.photoFailed(CameraError.save(error?.localizedDescription ?? "未知错误"))
            }
        }
    }

    /// 用与预览完全相同的 FilterEngine 处理整张照片，保留 EXIF / 色彩空间，输出 JPEG。
    private func renderFiltered(_ data: Data, settings: StyleSettings, cropAspect: CGFloat?) -> Data? {
        guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let colorSpace = decoded.colorSpace ?? Self.sRGB
        let source = Self.cropped(decoded, toAspect: cropAspect)
        let snapshot = FilterEngine.shared.snapshot(for: settings)
        let grainScale = max(1, source.extent.width / 1280)
        let output = FilterEngine.shared.process(source, snapshot: snapshot, grainScale: grainScale)
        guard let cgImage = ciContext.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: colorSpace) else {
            return nil
        }

        var metadata: [CFString: Any] = [:]
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            metadata = props
        }
        metadata[kCGImagePropertyOrientation] = 1     // 方向已经烘焙进像素
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        metadata.removeValue(forKey: kCGImagePropertyPixelWidth)
        metadata.removeValue(forKey: kCGImagePropertyPixelHeight)
        metadata[kCGImageDestinationLossyCompressionQuality] = 0.95

        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return result as Data
    }

    /// 按取景器当前显示的宽高比居中裁剪（取景器全屏时，成片与所见一致）。
    private static func cropped(_ image: CIImage, toAspect aspect: CGFloat?) -> CIImage {
        guard let aspect, aspect > 0 else { return image }
        let e = image.extent
        let current = e.width / e.height
        var rect = e
        if aspect < current {
            let w = e.height * aspect
            rect = CGRect(x: e.minX + (e.width - w) / 2, y: e.minY, width: w, height: e.height)
        } else if aspect > current {
            let h = e.width / aspect
            rect = CGRect(x: e.minX, y: e.minY + (e.height - h) / 2, width: e.width, height: h)
        }
        rect = rect.integral
        return image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private static func makeThumbnail(from data: Data, maxPixel: Int = 200) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: Video recording

    func startRecording() {
        guard mode == .video else { return }
        guard cameraReady else { message = CameraError.notReady.localizedDescription; return }
        guard !isRecording, !isFinalizingVideo, !isCapturingPhoto else { return }
        guard photosAddAllowed() else { message = CameraError.photosDenied.localizedDescription; return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YCam-Video-\(UUID().uuidString).mov")
        let audioSettings = makeAudioSettings()
        isRecording = true
        recordingStart = Date()
        if !micAvailable { message = "未获得麦克风权限：本次视频将没有声音" }
        dataQueue.async { self.recorder.arm(url: url, audioSettings: audioSettings) }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingStart = nil
        isFinalizingVideo = true
        let styleName = styleSettings.isIdentity ? "" : "（风格：\(styleSettings.style.title)）"
        dataQueue.async {
            self.recorder.finish { result in
                switch result {
                case .success(let url):
                    self.saveVideo(url, styleName: styleName)
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isFinalizingVideo = false
                        self.message = "录制失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func makeAudioSettings() -> [String: Any]? {
        guard micAvailable else { return nil }
        if let raw = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov),
           let settings = raw as? [String: Any] {
            return settings
        }
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96000
        ]
    }

    private func saveVideo(_ url: URL, styleName: String) {
        PHPhotoLibrary.shared().performChanges({
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                self.isFinalizingVideo = false
                if success {
                    self.message = "视频已保存到照片图库\(styleName)"
                } else {
                    self.message = CameraError.save(error?.localizedDescription ?? "未知错误").localizedDescription
                }
            }
        }
    }

    // MARK: Frame pipeline（dataQueue）

    private func handleVideo(_ sample: CMSampleBuffer) {
        autoreleasepool {
            guard let source = CMSampleBufferGetImageBuffer(sample) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let width = CVPixelBufferGetWidth(source)
            let height = CVPixelBufferGetHeight(source)
            guard let target = makePixelBuffer(width: width, height: height) else { return }

            // 同一帧只处理一次：处理后的画面既用于取景器，也用于录像。
            let processed = FilterEngine.shared.process(CIImage(cvPixelBuffer: source))
            ciContext.render(processed, to: target,
                             bounds: CGRect(x: 0, y: 0, width: width, height: height),
                             colorSpace: Self.sRGB)
            display(target, pts: pts)
            recorder.appendVideo(target, pts: pts)
        }
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pixelPool == nil || pixelPoolSize.width != width || pixelPoolSize.height != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            pixelPool = pool
            pixelPoolSize = (width, height)
        }
        guard let pool = pixelPool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }

    private func display(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let layer = displayLayer, let sample = Self.makeSampleBuffer(pixelBuffer, pts: pts) else { return }
        if layer.status == .failed { layer.flush() }
        if layer.isReadyForMoreMediaData { layer.enqueue(sample) }
    }

    private static func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer, pts: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return nil }
        // 立即显示，不依赖时间基准。
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}

// MARK: - Sample buffer delegates（视频帧 + 音频）

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            handleVideo(sampleBuffer)
        } else if output === audioOutput {
            recorder.appendAudio(sampleBuffer)
        }
    }
}

// MARK: - Photo delegate

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async { self.shutterPulse += 1 }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let job = activeJob() else { return }
        if let error {
            job.error = error
            return
        }
        job.data = photo.fileDataRepresentation()
        if job.data == nil { job.error = CameraError.capture("无法读取照片数据") }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                     duration: CMTime,
                     photoDisplayTime: CMTime,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        guard let job = activeJob() else { return }
        if error == nil {
            job.producedLiveURL = outputFileURL
        } else {
            try? FileManager.default.removeItem(at: outputFileURL)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let job = activeJob() else { return }
        if let failure = error ?? job.error {
            discardLiveMovie(job)
            photoFailed(CameraError.capture(failure.localizedDescription))
            return
        }
        guard let data = job.data else {
            discardLiveMovie(job)
            photoFailed(CameraError.capture("没有拿到照片数据"))
            return
        }
        processingQueue.async { self.finishPhoto(job, data: data) }
    }
}
