import AVFoundation
import Combine
import UIKit

/// Receives frames on the capture queue and forwards them to the active NDI sender.
final class FrameForwarder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var sender: NDISender?

    func setSender(_ sender: NDISender?) {
        lock.lock(); self.sender = sender; lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ns = Int64(CMTimeGetSeconds(pts) * 1_000_000_000)
        lock.lock(); let target = sender; lock.unlock()
        target?.send(pixelBuffer: pixelBuffer, timestampNs: ns)
    }
}

/// Main-actor view model bridging `CaptureEngine` + `NDISender` to SwiftUI.
@MainActor
final class CameraCaptureController: ObservableObject {

    @Published private(set) var status: CaptureEngine.Status = .idle
    @Published private(set) var isBroadcasting = false
    @Published private(set) var activeFormat: String = "—"
    @Published private(set) var connectionCount = 0
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState

    let settings: BroadcastSettings
    private let engine = CaptureEngine()
    private var sender: NDISender?
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var activeFps: Int32 = 30

    var session: AVCaptureSession { engine.session }

    init(settings: BroadcastSettings) {
        self.settings = settings

        engine.onStatus = { [weak self] status in
            MainActor.assumeIsolated { self?.status = status }
        }
        engine.onActiveFormat = { [weak self] w, h, fps in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.activeFps = fps
                self.activeFormat = "\(w)×\(h) @\(fps)"
                self.sender?.setFrameRate(fps: fps)
            }
        }

        // Re-apply capture config whenever settings change.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.engine.apply(config: self.settings.snapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
            .store(in: &cancellables)
    }

    func start() { engine.start(config: settings.snapshot) }

    func stop() {
        stopBroadcast()
        engine.stop()
    }

    func switchCamera() { engine.switchCamera() }

    func toggleBroadcast() {
        isBroadcasting ? stopBroadcast() : startBroadcast()
    }

    private func startBroadcast() {
        guard sender == nil else { return }
        let s = NDISender(sourceName: settings.sourceName)
        s.setFrameRate(fps: activeFps)
        sender = s
        engine.setSender(s)
        isBroadcasting = true

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.connectionCount = self?.engine.connectionCount ?? 0
            }
        }
    }

    private func stopBroadcast() {
        pollTimer?.invalidate(); pollTimer = nil
        engine.setSender(nil)
        sender?.stop()
        sender = nil
        isBroadcasting = false
        connectionCount = 0
    }
}
