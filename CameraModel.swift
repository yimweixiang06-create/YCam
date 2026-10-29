import AVFoundation
import Photos
import SwiftUI
import UIKit
import CoreImage
import ImageIO

// MARK: - Shared types

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

/// 一次拍照任务（按下快门瞬间的状态在这里固定下来）。
private final class PhotoJob {
    let settings: StyleSettings
    let requestedLiveURL: URL?
    let cropAspect: CGFloat?       // 取景框不是 4:3 时：按取景框居中裁剪成片
    let preferHEIC: Bool
    var data: Data?
    var rawData: Data?
    var producedLiveURL: URL?
    var error: Error?

    init(settings: StyleSettings, requestedLiveURL: URL?, cropAspect: CGFloat?, preferHEIC: Bool) {
        self.settings = settings
        self.requestedLiveURL = requestedLiveURL
        self.cropAspect = cropAspect
        self.preferHEIC = preferHEIC
    }
}

// MARK: - CameraModel

final class CameraModel: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: Published UI state（只在主线程修改；变化频繁的放在 zoom / histogram 里）

    @Published private(set) var permission: PermissionState = .unknown
    @Published private(set) var cameraReady = false
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var flashAvailable = false
    @Published var flashSetting: FlashSetting = .off
    @Published private(set) var livePhotoSupported = false
    @Published var livePhotoEnabled = true
    @Published var nightEnabled = false
    @Published var aspect: AspectSetting = .fourThree
    @Published var timerSeconds = 0
    @Published private(set) var timerCountdown: Int?
    @Published private(set) var micAvailable = false
    @Published private(set) var isCapturingPhoto = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizingVideo = false
    @Published private(set) var recordingStart: Date?
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var shutterPulse = 0
    @Published private(set) var personDetected = false
    @Published private(set) var controlsRevision = 0
    @Published var photoFormat: PhotoFormat = .heif
    @Published var photoResolution: PhotoResolutionChoice = .half
    @Published private(set) var rawSupported = false
    @Published private(set) var resolutionTitles: [String] = ["最大", "一半"]
    @Published private(set) var videoSpecs: [VideoSpec] = [VideoSpec(height: 1080, fps: 30)]
    @Published var videoSpec = VideoSpec(height: 1080, fps: 30)

    @Published var message: String? {
        didSet {
            if let message { DiagnosticsLog.shared.add("提示：\(message)") }
        }
    }

    /// 唯一的风格状态：名称 / 卡片 / 预览 / 照片 / 视频 / 实况都读取它。
    @Published var styleSettings = StyleSettings() {
        didSet {
            FilterEngine.shared.update(styleSettings)
            if styleSettings.lighting == .off && styleSettings.depth < 0.001 {
                PersonSegmenter.shared.reset()
            }
        }
    }

    let zoom = ZoomModel()
    let histogram = HistogramModel()

    // 滑块类设置：面板自己保存本地状态，这里只记录当前值（不发布，避免整个界面跟着刷新）
    private(set) var exposureBias: Float = 0
    private(set) var focusLens: Float?
    private(set) var shutterSeconds: Double?
    private(set) var whiteBalanceKelvin: Int?
    private(set) var histogramEnabled = false
    private(set) var exposureRange: ClosedRange<Float> = -2...2
    private(set) var shutterRange: ClosedRange<Double> = (1.0 / 2000)...(1.0 / 2)

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
    private static let maxPreviewLongEdge: CGFloat = 1280                  // 照片 / 人像取景的处理分辨率上限

    private var framesProcessed = 0                                        // 仅 dataQueue
    private var frameCounter = 0                                           // 仅 dataQueue
    private var lastLoggedFrameSize = (width: 0, height: 0)                // 仅 dataQueue
    private var dataIsVideoMode = false                                    // 仅 dataQueue
    private var lastPersonFlag = false                                     // 仅 dataQueue

    private var zoomBase: CGFloat = 1                                      // sessionQueue
    private var zoomCurrent: CGFloat = 1                                   // sessionQueue
    private var maxPhotoDims = CMVideoDimensions(width: 0, height: 0)      // sessionQueue
    private var halfPhotoDims = CMVideoDimensions(width: 0, height: 0)     // sessionQueue
    private var shutterBaseline: (duration: Double, iso: Float)?           // sessionQueue
    private var lastPortraitLighting: PortraitLighting = .natural
    private var portraitDepth: Double = 0.55
    private var photoDepth: Double = 0
    private var timerTask: Task<Void, Never>?
    private lazy var pointConverter: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

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
        DiagnosticsLog.shared.add("权限：相机=\(cameraGranted ? "允许" : "拒绝")")
        guard cameraGranted else { return }

        // 麦克风 / 照片权限被拒绝不会阻止取景，只会让对应功能给出明确提示。
        let micGranted = await authorize(.audio)
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        let photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly).rawValue
        DiagnosticsLog.shared.add("权限：麦克风=\(micGranted ? "允许" : "拒绝")，照片添加权限状态码=\(photosStatus)")
        DiagnosticsLog.shared.add("设备：\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
        sessionQueue.async { self.configureAndRun(withAudio: micGranted) }
    }

    func sceneWillResignActive() {
        cancelTimer()
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
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            DiagnosticsLog.shared.add("相机会话错误：\(error?.domain ?? "?") 代码 \(error?.code ?? 0)：\(error?.localizedDescription ?? "未知")")
            if self.isRecording { self.stopRecording() }
            self.message = "相机发生错误，正在尝试恢复"
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning { self.session.startRunning() }
            }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            DiagnosticsLog.shared.add("相机被系统打断，原因码=\(reason)")
            if self.isRecording { self.stopRecording() }
            self.message = "相机被系统暂时占用（如来电或多任务）"
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            DiagnosticsLog.shared.add("相机打断结束，恢复运行")
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning { self.session.startRunning() }
            }
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { self?.resumeContinuousFocus() }
        })
    }

    // MARK: Session configuration（sessionQueue）

    /// 后置优先用多摄虚拟镜头（可 0.5× / 1× / 2× / 长焦无缝变焦），没有再退回普通广角。
    private static func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            for type in types {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
            }
            return nil
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func configureAndRun(withAudio: Bool) {
        if !isConfigured {
            guard configureSession() else { return }
            isConfigured = true
        }
        if withAudio { addAudioIfNeeded() }
        if !session.isRunning { session.startRunning() }
        DiagnosticsLog.shared.add("相机会话：running=\(session.isRunning)，预设=\(session.sessionPreset.rawValue)，设备=\(videoInput?.device.localizedName ?? "无")，实况支持=\(photoOutput.isLivePhotoCaptureSupported)，麦克风=\(audioInput != nil)")
        publishCapabilities()
        scheduleFrameWatchdog()
    }

    /// 相机启动 4 秒后检查是否真的收到了画面；一帧都没有就明确提示，并写进诊断日志。
    private func scheduleFrameWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            self.dataQueue.async {
                let count = self.framesProcessed
                let layerStatus = self.displayLayer?.sampleBufferRenderer.status.rawValue ?? -1
                DiagnosticsLog.shared.add("4 秒检查：已处理 \(count) 帧；取景层状态码=\(layerStatus)")
                if count == 0 { self.post("没有收到相机画面（0 帧）。长按右上角“⋯”打开诊断日志") }
            }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.cameraDevice(position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DiagnosticsLog.shared.add("配置失败：找不到可用的后置相机，或被其他 App 占用")
            post("无法使用相机（设备不支持或被其他 App 占用）")
            return false
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            DiagnosticsLog.shared.add("配置失败：无法添加拍照输出")
            post("无法创建拍照输出")
            return false
        }
        session.addOutput(photoOutput)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: dataQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            DiagnosticsLog.shared.add("配置失败：无法添加实时画面输出")
            post("无法创建实时画面输出")
            return false
        }
        session.addOutput(videoOutput)
        session.commitConfiguration()

        applyConnectionSettings()
        if photoOutput.isLivePhotoCaptureSupported {
            photoOutput.isLivePhotoCaptureEnabled = true
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        configureDeviceCapabilities(device)
        DiagnosticsLog.shared.add("相机设备：\(device.localizedName)，镜头数=\(device.constituentDevices.count)")
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
            self.livePhotoSupported = live
            self.position = devicePosition
            self.micAvailable = mic
            self.cameraReady = running
        }
    }

    /// 根据当前镜头读出：变焦档位、照片分辨率 / RAW、视频规格、曝光 / 快门范围。
    private func configureDeviceCapabilities(_ device: AVCaptureDevice) {
        configureZoom(for: device)
        configurePhotoOptions(for: device)
        let specs = computeVideoSpecs(for: device)
        let minBias = device.minExposureTargetBias
        let maxBias = device.maxExposureTargetBias
        let minDuration = max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), 1.0 / 8000)
        let maxDuration = min(CMTimeGetSeconds(device.activeFormat.maxExposureDuration), 0.5)
        DispatchQueue.main.async {
            self.videoSpecs = specs
            if !specs.contains(self.videoSpec) {
                self.videoSpec = specs.first(where: { $0.height == 1080 && $0.fps == 30 }) ?? specs[0]
            }
            self.exposureRange = max(-3, minBias)...max(max(-3, minBias), min(3, maxBias))
            self.shutterRange = minDuration...max(minDuration, maxDuration)
            self.controlsRevision += 1
        }
        DiagnosticsLog.shared.add("视频规格：\(specs.map { $0.title }.joined(separator: "、"))")
    }

    // MARK: Zoom

    private func configureZoom(for device: AVCaptureDevice) {
        var base: CGFloat = 1
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        if device.position == .back, hasUltraWide, let first = switchOvers.first {
            base = first          // 虚拟镜头的 1.0 是超广角，主摄在第一个切换点
        }
        zoomBase = base

        var displays: [CGFloat] = [1]
        if device.position == .back {
            if hasUltraWide { displays.append(1 / base) }
            if device.maxAvailableVideoZoomFactor >= base * 2 { displays.append(2) }
            if switchOvers.count >= 2 {
                let tele = switchOvers[1] / base
                if tele > 2.2 { displays.append(tele) }
            }
        }
        var stops: [ZoomStop] = []
        for value in displays.sorted() {
            if stops.contains(where: { abs($0.display - value) < 0.1 }) { continue }
            stops.append(ZoomStop(label: value < 0.95 ? ".5" : "\(Int(value.rounded()))", display: value))
        }

        zoomCurrent = 1
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, base))
            device.unlockForConfiguration()
        } catch {
            DiagnosticsLog.shared.add("设置初始变焦失败：\(error.localizedDescription)")
        }
        DiagnosticsLog.shared.add("变焦档位：\(stops.map { $0.label }.joined(separator: " / "))，主摄基准=\(base)")
        DispatchQueue.main.async {
            self.zoom.stops = stops
            self.zoom.display = 1
        }
    }

    /// 双指捏合或点倍率按钮。display：界面上的倍率（1 = 主摄）。
    func setZoom(display: CGFloat, ramp: Bool = false) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let upper = min(device.maxAvailableVideoZoomFactor, self.zoomBase * 10)
            let factor = min(upper, max(device.minAvailableVideoZoomFactor, display * self.zoomBase))
            do {
                try device.lockForConfiguration()
                if ramp {
                    device.ramp(toVideoZoomFactor: factor, withRate: 8)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = factor
                }
                device.unlockForConfiguration()
            } catch {
                self.post("变焦失败：\(error.localizedDescription)")
                return
            }
            let shown = factor / self.zoomBase
            self.zoomCurrent = shown
            DispatchQueue.main.async { self.zoom.display = shown }
        }
    }

    // MARK: Photo options / video specs

    private func configurePhotoOptions(for device: AVCaptureDevice) {
        let list = device.activeFormat.supportedMaxPhotoDimensions
        func area(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }
        guard let largest = list.max(by: { area($0) < area($1) }) else { return }
        let target = area(largest) / 2
        let half = list.min(by: { abs(area($0) - target) < abs(area($1) - target) }) ?? largest
        maxPhotoDims = largest
        halfPhotoDims = half
        if photoOutput.maxPhotoDimensions.width != largest.width || photoOutput.maxPhotoDimensions.height != largest.height {
            photoOutput.maxPhotoDimensions = largest
        }
        let raw = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        let titles = [
            "\(Int((Double(area(largest)) / 1_000_000).rounded())) MP",
            "\(Int((Double(area(half)) / 1_000_000).rounded())) MP"
        ]
        DiagnosticsLog.shared.add("照片分辨率：最大 \(largest.width)×\(largest.height)，一半 \(half.width)×\(half.height)，RAW=\(raw)")
        DispatchQueue.main.async {
            self.rawSupported = raw
            self.resolutionTitles = titles
            if !raw && self.photoFormat == .raw { self.photoFormat = .heif }
        }
    }

    private func computeVideoSpecs(for device: AVCaptureDevice) -> [VideoSpec] {
        var found = Set<VideoSpec>()
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let isHD = dims.width == 1920 && dims.height == 1080
            let is4K = dims.width == 3840 && dims.height == 2160
            guard isHD || is4K else { continue }
            for fps in [30, 60] {
                let wanted = Double(fps)
                if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= wanted && wanted <= $0.maxFrameRate }) {
                    found.insert(VideoSpec(height: isHD ? 1080 : 2160, fps: fps))
                }
            }
        }
        let sorted = found.sorted { ($0.height, $0.fps) < ($1.height, $1.fps) }
        return sorted.isEmpty ? [VideoSpec(height: 1080, fps: 30)] : sorted
    }

    /// 视频模式：设置分辨率预设，并找一个同分辨率、支持目标帧率的 8 位格式。
    private func applyVideoSpec(_ spec: VideoSpec) {
        guard isConfigured, let device = videoInput?.device else { return }
        let is4K = spec.height >= 2160
        let targetWidth: Int32 = is4K ? 3840 : 1920
        let targetHeight: Int32 = is4K ? 2160 : 1080
        session.beginConfiguration()
        let preset: AVCaptureSession.Preset = is4K ? .hd4K3840x2160 : .hd1920x1080
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }
        session.commitConfiguration()

        let wanted = Double(spec.fps)
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == targetWidth, dims.height == targetHeight else { return false }
            return format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= wanted && wanted <= $0.maxFrameRate }
        }
        let preferred = candidates.first {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } ?? candidates.first
        do {
            try device.lockForConfiguration()
            if let format = preferred, device.activeFormat != format {
                device.activeFormat = format
            }
            let duration = CMTime(value: 1, timescale: CMTimeScale(spec.fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
            DiagnosticsLog.shared.add("视频规格已设置：\(spec.title)")
        } catch {
            post("无法设置视频规格：\(error.localizedDescription)")
        }
    }

    func selectVideoSpec(_ spec: VideoSpec) {
        videoSpec = spec
        guard mode == .video, !isRecording, !isFinalizingVideo else { return }
        sessionQueue.async {
            self.applyVideoSpec(spec)
            if let device = self.videoInput?.device { self.reapplyDeviceSettings(device) }
            self.applyConnectionSettings()
        }
    }

    // MARK: Mode

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode else { return }
        guard !isRecording, !isCapturingPhoto, !isFinalizingVideo, timerCountdown == nil else { return }
        mode = newMode

        // 人像光效 / 景深只在人像模式里生效
        if newMode == .portrait {
            photoDepth = styleSettings.depth
            styleSettings.lighting = lastPortraitLighting
            styleSettings.depth = portraitDepth
        } else if mode != .portrait, styleSettings.lighting != .off {
            lastPortraitLighting = styleSettings.lighting
            portraitDepth = styleSettings.depth
            styleSettings.lighting = .off
            styleSettings.depth = photoDepth
        }

        let wantsVideo = newMode == .video
        let spec = videoSpec
        dataQueue.async { self.dataIsVideoMode = wantsVideo }
        sessionQueue.async {
            self.applyMode(newMode, spec: spec)
            self.publishCapabilities()
        }
    }

    private func applyMode(_ mode: CaptureMode, spec: VideoSpec) {
        guard isConfigured, let device = videoInput?.device else { return }
        switch mode {
        case .photo, .portrait:
            session.beginConfiguration()
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            session.commitConfiguration()
            setTorch(false)
            configurePhotoOptions(for: device)
        case .video:
            applyVideoSpec(spec)
        }
        applyConnectionSettings()
        reapplyDeviceSettings(device)
    }

    /// 切换预设 / 格式后，系统会重置一部分设备设置，这里统一补回。
    private func reapplyDeviceSettings(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let factor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, zoomCurrent * zoomBase))
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        } catch {
            DiagnosticsLog.shared.add("恢复变焦失败：\(error.localizedDescription)")
        }
        if exposureBias != 0 { applyExposureBias(exposureBias, device) }
        if focusLens != nil { applyFocus(focusLens, device) }
        if shutterSeconds != nil { applyShutter(shutterSeconds, device) }
        if whiteBalanceKelvin != nil { applyWhiteBalance(whiteBalanceKelvin, device) }
        applyNight(nightEnabled, device)
    }

    // MARK: Flash / night

    /// 照片模式：闪光灯在拍照时按 自动 / 开 / 关 触发；视频模式：“开”= 手电筒。
    func cycleFlash() {
        guard flashAvailable else {
            message = "当前镜头不支持闪光灯"
            return
        }
        flashSetting = flashSetting.next
        let torchOn = flashSetting == .on && mode == .video
        sessionQueue.async { self.setTorch(torchOn) }
        markControlsChanged()
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

    func toggleNight() {
        nightEnabled.toggle()
        let on = nightEnabled
        sessionQueue.async {
            if let device = self.videoInput?.device { self.applyNight(on, device) }
        }
        message = on ? "夜间模式：自动（弱光下自动提亮并多帧合成）" : "夜间模式已关闭"
        markControlsChanged()
    }

    private func applyNight(_ on: Bool, _ device: AVCaptureDevice) {
        guard device.isLowLightBoostSupported else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyEnablesLowLightBoostWhenAvailable = on
            device.unlockForConfiguration()
        } catch {
            DiagnosticsLog.shared.add("夜间模式设置失败：\(error.localizedDescription)")
        }
    }

    // MARK: Exposure / focus / shutter / white balance

    func setExposureBias(_ ev: Float) {
        exposureBias = ev
        sessionQueue.async {
            if let device = self.videoInput?.device { self.applyExposureBias(ev, device) }
        }
    }

    private func applyExposureBias(_ ev: Float, _ device: AVCaptureDevice) {
        let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, ev))
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            post("曝光补偿设置失败：\(error.localizedDescription)")
        }
    }

    /// lens：0（最近）… 1（无穷远）；nil = 自动对焦。
    func setFocusLens(_ lens: Float?) {
        focusLens = lens
        sessionQueue.async {
            if let device = self.videoInput?.device { self.applyFocus(lens, device) }
        }
    }

    private func applyFocus(_ lens: Float?, _ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if let lens {
                if device.isLockingFocusWithCustomLensPositionSupported {
                    device.setFocusModeLocked(lensPosition: min(1, max(0, lens)), completionHandler: nil)
                } else {
                    post("此镜头不支持手动对焦")
                }
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            post("对焦设置失败：\(error.localizedDescription)")
        }
    }

    /// seconds：手动快门时间（秒）；nil = 自动。会自动调整 ISO 来保持亮度。
    func setShutterSeconds(_ seconds: Double?) {
        let wasAuto = shutterSeconds == nil
        shutterSeconds = seconds
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            if seconds != nil, wasAuto {
                self.shutterBaseline = (CMTimeGetSeconds(device.exposureDuration), device.iso)
            }
            if seconds == nil { self.shutterBaseline = nil }
            self.applyShutter(seconds, device)
        }
    }

    private func applyShutter(_ seconds: Double?, _ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if let seconds {
                if device.isExposureModeSupported(.custom) {
                    let format = device.activeFormat
                    let minDuration = CMTimeGetSeconds(format.minExposureDuration)
                    let maxDuration = CMTimeGetSeconds(format.maxExposureDuration)
                    let clamped = min(maxDuration, max(minDuration, seconds))
                    let base = shutterBaseline ?? (CMTimeGetSeconds(device.exposureDuration), device.iso)
                    let wantedISO = base.iso * Float(base.duration / clamped)
                    let iso = min(format.maxISO, max(format.minISO, wantedISO))
                    let duration = CMTimeMakeWithSeconds(clamped, preferredTimescale: 1_000_000_000)
                    device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
                } else {
                    post("此镜头不支持手动快门")
                }
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            post("快门设置失败：\(error.localizedDescription)")
        }
    }

    /// kelvin：色温；nil = 自动（根据画面实时分析，默认）。
    func setWhiteBalance(kelvin: Int?) {
        whiteBalanceKelvin = kelvin
        sessionQueue.async {
            if let device = self.videoInput?.device { self.applyWhiteBalance(kelvin, device) }
        }
    }

    private func applyWhiteBalance(_ kelvin: Int?, _ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if let kelvin {
                if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(kelvin), tint: 0)
                    var gains = device.deviceWhiteBalanceGains(for: values)
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = min(maxGain, max(1, gains.redGain))
                    gains.greenGain = min(maxGain, max(1, gains.greenGain))
                    gains.blueGain = min(maxGain, max(1, gains.blueGain))
                    device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                } else {
                    post("此镜头不支持手动白平衡")
                }
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            post("白平衡设置失败：\(error.localizedDescription)")
        }
    }

    func setHistogram(_ on: Bool) {
        histogramEnabled = on
        markControlsChanged()
    }

    /// 滑块松手后调用，让抽屉里的图标 / 状态刷新。
    func markControlsChanged() {
        DispatchQueue.main.async { self.controlsRevision += 1 }
    }

    // MARK: Tap to focus

    /// point：点在取景框里的位置；viewSize：取景框大小。
    func focus(atViewPoint point: CGPoint, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0, cameraReady else { return }
        pointConverter.frame = CGRect(origin: .zero, size: viewSize)
        let devicePoint = pointConverter.captureDevicePointConverted(fromLayerPoint: point)
        let manualFocus = focusLens != nil
        let manualShutter = shutterSeconds != nil
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if !manualFocus, device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if !manualShutter, device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                self.post("对焦失败：\(error.localizedDescription)")
            }
        }
    }

    private func resumeContinuousFocus() {   // sessionQueue
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if focusLens == nil, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if shutterSeconds == nil, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = false
            device.unlockForConfiguration()
        } catch {
            DiagnosticsLog.shared.add("恢复连续对焦失败：\(error.localizedDescription)")
        }
    }

    // MARK: Flip

    func flipCamera() {
        guard cameraReady, !isRecording, !isCapturingPhoto, !isFinalizingVideo, timerCountdown == nil else { return }
        let target: AVCaptureDevice.Position = position == .back ? .front : .back
        let currentMode = mode
        let spec = videoSpec
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
            self.configureDeviceCapabilities(device)
            if currentMode == .video { self.applyVideoSpec(spec) }
            self.reapplyDeviceSettings(device)
            self.publishCapabilities()
            DispatchQueue.main.async {
                if currentMode == .video, self.flashSetting == .on, device.hasTorch {
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

    // MARK: Shutter + timer

    /// 快门：先按计时器倒计时，再拍照 / 开始录像；录像中再按 = 停止；倒计时中再按 = 取消。
    func triggerCapture(cropAspect: CGFloat?) {
        if timerCountdown != nil {
            cancelTimer()
            return
        }
        if mode == .video, isRecording {
            stopRecording()
            return
        }
        guard cameraReady else {
            message = CameraError.notReady.localizedDescription
            return
        }
        guard timerSeconds > 0 else {
            performCapture(cropAspect: cropAspect)
            return
        }
        let seconds = timerSeconds
        timerCountdown = seconds
        timerTask = Task { @MainActor [weak self] in
            var left = seconds
            while left > 0 {
                guard let self, !Task.isCancelled else { return }
                self.timerCountdown = left
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                left -= 1
            }
            guard let self, !Task.isCancelled else { return }
            self.timerCountdown = nil
            self.performCapture(cropAspect: cropAspect)
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerCountdown = nil
    }

    private func performCapture(cropAspect: CGFloat?) {
        switch mode {
        case .photo, .portrait:
            capturePhoto(cropAspect: cropAspect)
        case .video:
            if isRecording { stopRecording() } else { startRecording() }
        }
    }

    // MARK: Photo capture

    private func capturePhoto(cropAspect: CGFloat?) {
        guard mode != .video else { return }
        guard cameraReady else { message = CameraError.notReady.localizedDescription; return }
        guard !isCapturingPhoto, !isRecording, !isFinalizingVideo else { return }
        guard photosAddAllowed() else { message = CameraError.photosDenied.localizedDescription; return }

        let style = styleSettings                    // 按下快门这一刻的风格状态
        let flash = flashSetting
        let format = photoFormat
        let resolution = photoResolution
        let night = nightEnabled
        let isPortrait = mode == .portrait
        // 实况：摄影风格 / 滤镜 / 色调板都可以用（动态部分会逐帧套同样的风格）；
        // 人像光效 / 景深、RAW、最大分辨率、非 4:3 裁剪时不能配实况。
        let wantLive = livePhotoEnabled && livePhotoSupported && format == .heif && resolution == .half
            && !isPortrait && cropAspect == nil && style.lighting == .off && style.depth < 0.001
        isCapturingPhoto = true
        DiagnosticsLog.shared.add("拍照：模式=\(mode.rawValue)，风格=\(style.style.title)，滤镜=\(style.filter.title)，光效=\(style.lighting.title)，景深=\(style.depth)，格式=\(format.rawValue)，分辨率=\(resolution.rawValue)，实况=\(wantLive)")

        sessionQueue.async {
            let (settings, hevc) = self.makePhotoSettings(format: format, resolution: resolution, flash: flash, night: night)
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
            self.setJob(PhotoJob(settings: style, requestedLiveURL: liveURL, cropAspect: cropAspect, preferHEIC: hevc))
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func makePhotoSettings(format: PhotoFormat, resolution: PhotoResolutionChoice,
                                   flash: FlashSetting, night: Bool) -> (AVCapturePhotoSettings, Bool) {
        let hevc = photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let processed: [String: Any] = [AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.jpeg]
        let settings: AVCapturePhotoSettings
        var isRaw = false
        if format == .raw, let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: processed)
            isRaw = true
        } else {
            settings = AVCapturePhotoSettings(format: processed)
        }
        if !isRaw {
            let dims = resolution == .max ? maxPhotoDims : halfPhotoDims
            if dims.width > 0, dims.height > 0 { settings.maxPhotoDimensions = dims }
        }
        if let device = videoInput?.device, device.hasFlash {
            switch flash {
            case .on:
                if photoOutput.supportedFlashModes.contains(.on) { settings.flashMode = .on }
            case .auto:
                if photoOutput.supportedFlashModes.contains(.auto) { settings.flashMode = .auto }
            case .off:
                break
            }
        }
        settings.photoQualityPrioritization = night ? .quality : .balanced
        return (settings, hevc)
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
        let nsError = error as NSError
        DiagnosticsLog.shared.add("拍照 / 保存失败：\(nsError.domain) 代码 \(nsError.code)：\(error.localizedDescription)")
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

    /// 在后台线程完成：风格处理 →（实况的动态部分套同样的风格）→ 写入相册。
    private func finishPhoto(_ job: PhotoJob, data: Data) {
        var output = data
        var notes: [String] = []
        var liveForPairing = job.producedLiveURL
        var tempFiles: [URL] = []

        let needsProcessing = !job.settings.isIdentity || job.cropAspect != nil
        if needsProcessing {
            if let processed = renderFiltered(data, settings: job.settings, cropAspect: job.cropAspect, preferHEIC: job.preferHEIC) {
                output = processed.data
                if let note = processed.note { notes.append(note) }
                if let live = job.producedLiveURL {
                    let snapshot = FilterEngine.shared.snapshot(for: job.settings)
                    if let styled = LivePhotoStyler.style(movie: live, snapshot: snapshot, context: ciContext) {
                        tempFiles.append(styled)
                        liveForPairing = styled
                        DiagnosticsLog.shared.add("实况动态部分已套用风格")
                    } else {
                        notes.append("实况的动态部分未能套用风格，保留了原始动态")
                        DiagnosticsLog.shared.add("实况动态部分套用风格失败，退回原始动态")
                    }
                }
            } else {
                notes.append("处理失败，已保存未处理的原图")
            }
        }
        if let live = job.producedLiveURL { tempFiles.append(live) }
        if let requested = job.requestedLiveURL { tempFiles.append(requested) }

        let thumbnail = Self.makeThumbnail(from: output)
        let styleName = job.settings.isIdentity ? "" : "（\(job.settings.style.title)）"
        let finalOutput = output
        let finalNotes = notes
        let finalLive = liveForPairing
        let rawData = job.rawData
        let cleanupFiles = tempFiles

        performSave(photo: finalOutput, raw: rawData, live: finalLive) { success, error in
            if success {
                let base = finalLive != nil ? "实况照片已保存到照片图库" : "照片已保存到照片图库"
                let extra = finalNotes.isEmpty ? "" : "；" + finalNotes.joined(separator: "；")
                for url in cleanupFiles { try? FileManager.default.removeItem(at: url) }
                self.photoSucceeded(text: base + styleName + extra, thumbnail: thumbnail)
            } else if finalLive != nil {
                // 实况配对失败：退回只保存静态照片，并明确告诉用户
                self.performSave(photo: finalOutput, raw: rawData, live: nil) { ok, err in
                    for url in cleanupFiles { try? FileManager.default.removeItem(at: url) }
                    if ok {
                        self.photoSucceeded(text: "照片已保存（实况配对失败，只保存了静态照片）" + styleName, thumbnail: thumbnail)
                    } else {
                        self.photoFailed(CameraError.save(err?.localizedDescription ?? error?.localizedDescription ?? "未知错误"))
                    }
                }
            } else {
                for url in cleanupFiles { try? FileManager.default.removeItem(at: url) }
                self.photoFailed(CameraError.save(error?.localizedDescription ?? "未知错误"))
            }
        }
    }

    private func performSave(photo: Data, raw: Data?, live: URL?, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: .photo, data: photo, options: options)
            if let raw {
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.uniformTypeIdentifier = "com.adobe.raw-image"
                request.addResource(with: .alternatePhoto, data: raw, options: rawOptions)
            }
            if let live {
                let movieOptions = PHAssetResourceCreationOptions()
                movieOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: live, options: movieOptions)
            }
        }, completionHandler: completion)
    }

    /// 用与预览完全相同的 FilterEngine 处理整张照片，保留 EXIF / 色彩空间；HEIF 或 JPEG 输出。
    private func renderFiltered(_ data: Data, settings: StyleSettings, cropAspect: CGFloat?,
                                preferHEIC: Bool) -> (data: Data, note: String?)? {
        guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let colorSpace = decoded.colorSpace ?? Self.sRGB
        let source = Self.cropped(decoded, toAspect: cropAspect)
        let snapshot = FilterEngine.shared.snapshot(for: settings)

        var mask: CIImage?
        var note: String?
        if snapshot.needsMask {
            mask = PersonSegmenter.shared.segmentSync(source)
            if mask == nil { note = "未检测到人物，光效 / 景深没有生效" }
        }
        let grainScale = max(1, source.extent.width / 1280)
        let output = FilterEngine.shared.process(source, snapshot: snapshot, grainScale: grainScale, mask: mask)
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

        let types = preferHEIC ? ["public.heic", "public.jpeg"] : ["public.jpeg"]
        for type in types {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, type as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
            if CGImageDestinationFinalize(destination) { return (result as Data, note) }
        }
        return nil
    }

    /// 按取景框的宽高比居中裁剪（取景框不是 4:3 时，成片与所见一致）。
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

    private func startRecording() {
        guard mode == .video else { return }
        guard cameraReady else { message = CameraError.notReady.localizedDescription; return }
        guard !isRecording, !isFinalizingVideo, !isCapturingPhoto else { return }
        guard photosAddAllowed() else { message = CameraError.photosDenied.localizedDescription; return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YCam-Video-\(UUID().uuidString).mov")
        let audioSettings = makeAudioSettings()
        let spec = videoSpec
        isRecording = true
        recordingStart = Date()
        DiagnosticsLog.shared.add("开始录像：\(spec.title)，麦克风=\(micAvailable)，风格=\(styleSettings.style.title)，滤镜=\(styleSettings.filter.title)")
        if !micAvailable { message = "未获得麦克风权限：本次视频将没有声音" }
        dataQueue.async { self.recorder.arm(url: url, audioSettings: audioSettings, fps: spec.fps) }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingStart = nil
        isFinalizingVideo = true
        let styleName = styleSettings.isIdentity ? "" : "（\(styleSettings.style.title)）"
        dataQueue.async {
            self.recorder.finish { result in
                switch result {
                case .success(let url):
                    self.saveVideo(url, styleName: styleName)
                case .failure(let error):
                    DiagnosticsLog.shared.add("录像失败：\(error.localizedDescription)")
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
        if let settings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) {
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
                    DiagnosticsLog.shared.add("视频保存失败：\(error?.localizedDescription ?? "未知")")
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
            let srcW = CVPixelBufferGetWidth(source)
            let srcH = CVPixelBufferGetHeight(source)
            let snap = FilterEngine.shared.snapshot()

            framesProcessed &+= 1
            frameCounter &+= 1
            if lastLoggedFrameSize.width != srcW || lastLoggedFrameSize.height != srcH {
                lastLoggedFrameSize = (srcW, srcH)
                DiagnosticsLog.shared.add("相机画面尺寸：\(srcW)×\(srcH)，视频模式=\(dataIsVideoMode)")
            }
            if histogramEnabled, frameCounter % 6 == 0 { updateHistogram(from: source) }

            // 视频模式且不需要任何处理：直接用相机原始帧（省掉整条 GPU 流水线，4K / 60 帧也不卡）。
            if dataIsVideoMode, snap.isPassthroughColor {
                display(source, pts: pts)
                recorder.appendVideo(source, pts: pts)
                return
            }

            // 照片 / 人像取景只需要较低分辨率；视频按原分辨率处理（要写进文件）。
            let longEdge = CGFloat(max(srcW, srcH))
            let scale = dataIsVideoMode ? 1 : min(1, Self.maxPreviewLongEdge / longEdge)
            let width = max(2, Int((CGFloat(srcW) * scale).rounded()))
            let height = max(2, Int((CGFloat(srcH) * scale).rounded()))
            guard let target = makePixelBuffer(width: width, height: height) else { return }

            var mask: CIImage?
            if !dataIsVideoMode, snap.needsMask {
                PersonSegmenter.shared.submit(source)
                mask = PersonSegmenter.shared.current()
                let found = mask != nil
                if found != lastPersonFlag {
                    lastPersonFlag = found
                    DispatchQueue.main.async { self.personDetected = found }
                }
            }

            var image = CIImage(cvPixelBuffer: source)
            if scale < 1 {
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            let processed = FilterEngine.shared.process(image, snapshot: snap, mask: mask)
            ciContext.render(processed, to: target,
                             bounds: CGRect(x: 0, y: 0, width: width, height: height),
                             colorSpace: Self.sRGB)
            display(target, pts: pts)
            recorder.appendVideo(target, pts: pts)
        }
    }

    private func updateHistogram(from pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard image.extent.width > 0, image.extent.height > 0 else { return }
        let w = 64
        let h = 48
        let small = image.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / image.extent.width,
                                                            y: CGFloat(h) / image.extent.height))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        ciContext.render(small, toBitmap: &bytes, rowBytes: w * 4,
                         bounds: CGRect(x: 0, y: 0, width: w, height: h),
                         format: .RGBA8, colorSpace: Self.sRGB)
        var bins = [Float](repeating: 0, count: 64)
        var index = 0
        while index < bytes.count {
            let luma = 0.2126 * Float(bytes[index]) + 0.7152 * Float(bytes[index + 1]) + 0.0722 * Float(bytes[index + 2])
            bins[min(63, Int(luma / 4))] += 1
            index += 4
        }
        let peak = max(1, bins.max() ?? 1)
        let normalized = bins.map { $0 / peak }
        DispatchQueue.main.async { self.histogram.bins = normalized }
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
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        if renderer.isReadyForMoreMediaData { renderer.enqueue(sample) }
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
        if photo.isRawPhoto {
            job.rawData = photo.fileDataRepresentation()
        } else {
            job.data = photo.fileDataRepresentation()
            if job.data == nil { job.error = CameraError.capture("无法读取照片数据") }
        }
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
