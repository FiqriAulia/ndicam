import AVFoundation
import UIKit

/// Owns the `AVCaptureSession` and all of its configuration. Every mutation runs
/// on a private serial queue, so this type is safe to hold from the main actor
/// and call into from anywhere. UI state is surfaced via the `onStatus` callback
/// (always delivered on the main queue).
final class CaptureEngine: NSObject, @unchecked Sendable {

    enum Status: Equatable {
        case idle, unauthorized, running, failed(String)
    }

    let session = AVCaptureSession()
    var onStatus: ((Status) -> Void)?
    /// Actual capture parameters after format selection (may differ from requested).
    var onActiveFormat: ((_ width: Int32, _ height: Int32, _ fps: Int32) -> Void)?

    private let queue = DispatchQueue(label: "ndicam.session")
    private let videoQueue = DispatchQueue(label: "ndicam.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let forwarder = FrameForwarder()
    private var position: AVCaptureDevice.Position = .back
    private var config = CaptureConfig(width: 1280, height: 720, fps: 30, sourceName: "NDICam")
    private weak var currentSender: NDISender?

    // MARK: - Public API

    override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleRuntimeError),
                       name: .AVCaptureSessionRuntimeError, object: session)
        nc.addObserver(self, selector: #selector(handleInterruptionEnded),
                       name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    @objc private func handleRuntimeError(_ note: Notification) {
        // Transient errors (media services reset, resource contention) — retry.
        queue.asyncAfter(deadline: .now() + 0.5) {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            if self.session.isRunning { self.emit(.running) }
        }
    }

    @objc private func handleInterruptionEnded(_ note: Notification) {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
            if self.session.isRunning { self.emit(.running) }
        }
    }

    func start(config: CaptureConfig) {
        queue.async { self.config = config }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configure() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.queue.async { self.configure() } }
                else { self.emit(.unauthorized) }
            }
        default:
            emit(.unauthorized)
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.emit(.idle)
        }
    }

    func apply(config: CaptureConfig) {
        queue.async {
            guard config != self.config else { return }
            self.config = config
            if self.session.isRunning { self.configure() }
        }
    }

    func switchCamera() {
        queue.async {
            self.position = (self.position == .back) ? .front : .back
            self.configure()
        }
    }

    func setSender(_ sender: NDISender?) {
        currentSender = sender
        forwarder.setSender(sender)
    }

    // MARK: - Configuration (queue-isolated)

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority // we drive activeFormat ourselves

        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            emit(.failed("No usable camera"))
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        let active = selectFormat(for: device, config: config)

        if !session.outputs.contains(videoOutput) {
            // Native bi-planar NV12 straight from the camera: no BGRA conversion on
            // our side, and NDI compresses YUV natively (no RGB→YUV round-trip).
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(forwarder, queue: videoQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        }

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        emit(.running)
        DispatchQueue.main.async { self.onActiveFormat?(active.width, active.height, active.fps) }
    }

    /// Picks the `AVCaptureDevice.Format` closest to the requested resolution that
    /// can sustain the requested frame rate, and locks the frame duration to it.
    private func selectFormat(for device: AVCaptureDevice,
                              config: CaptureConfig) -> (width: Int32, height: Int32, fps: Int32) {
        let wantFps = Double(config.fps)
        let targetAR = Double(config.width) / Double(config.height)

        func dims(_ f: AVCaptureDevice.Format) -> CMVideoDimensions {
            CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        }
        func isYUV420(_ f: AVCaptureDevice.Format) -> Bool {
            let s = CMFormatDescriptionGetMediaSubType(f.formatDescription)
            return s == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || s == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        func supportsFps(_ f: AVCaptureDevice.Format) -> Bool {
            f.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= wantFps && wantFps <= $0.maxFrameRate
            }
        }
        func maxFps(_ f: AVCaptureDevice.Format) -> Double {
            f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        }
        func dimScore(_ d: CMVideoDimensions) -> Int {
            abs(Int(d.width) - Int(config.width)) + abs(Int(d.height) - Int(config.height))
        }

        let base = device.formats.filter { isYUV420($0) && supportsFps($0) }
        // Prefer formats with the requested aspect ratio (rejects 4:3 like 1440×1080).
        let matchingAR = base.filter { abs(Double(dims($0).width) / Double(dims($0).height) - targetAR) < 0.05 }
        let pool = matchingAR.isEmpty ? base : matchingAR

        let best = pool.min { a, b in
            let sa = dimScore(dims(a)), sb = dimScore(dims(b))
            if sa != sb { return sa < sb }
            return maxFps(a) < maxFps(b) // least headroom → least binning/crop
        } ?? device.activeFormat

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            let duration = CMTime(value: 1, timescale: CMTimeScale(config.fps))
            if best.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= wantFps && wantFps <= $0.maxFrameRate
            }) {
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
        } catch {
            emit(.failed("Camera format lock: \(error.localizedDescription)"))
        }

        let d = dims(best)
        let actualFps = supportsFps(best)
            ? config.fps
            : Int32(best.videoSupportedFrameRateRanges.first?.maxFrameRate ?? wantFps)
        return (d.width, d.height, actualFps)
    }

    // MARK: - Receiver count (device build only)

    var connectionCount: Int { currentSender?.connectionCount ?? 0 }

    private func emit(_ status: Status) {
        DispatchQueue.main.async { self.onStatus?(status) }
    }
}
