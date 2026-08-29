import CoreVideo
import Foundation
import os

/// Swift-facing handle for an NDI video source.
///
/// On the device build (`NDI_SDK_AVAILABLE`) frames are pushed to the network via
/// the `NDISenderBridge` Obj-C++ class. Simulator builds run a no-op stub so the
/// capture pipeline and UI still work there.
final class NDISender: @unchecked Sendable {

    private let log = Logger(subsystem: "com.fiqri.ndicam", category: "NDISender")
    private let name: String

    #if NDI_SDK_AVAILABLE
    private let bridge: NDISenderBridge
    #else
    private let frameCount = OSAllocatedUnfairLock(initialState: 0)
    #endif

    init(sourceName: String) {
        self.name = sourceName
        #if NDI_SDK_AVAILABLE
        self.bridge = NDISenderBridge(name: sourceName)
        log.info("NDI sender started: \(sourceName, privacy: .public)")
        #else
        log.warning("NDI stub active (no SDK). Source would be: \(sourceName, privacy: .public)")
        #endif
    }

    /// Advertise the real capture frame rate on the stream (e.g. 30/1 or 60/1).
    func setFrameRate(fps: Int32) {
        #if NDI_SDK_AVAILABLE
        bridge.setFrameRateN(fps, d: 1)
        #endif
    }

    func send(pixelBuffer: CVPixelBuffer, timestampNs: Int64) {
        #if NDI_SDK_AVAILABLE
        bridge.send(pixelBuffer, timestampNs: timestampNs)
        #else
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let n = frameCount.withLock { count -> Int in
            count += 1
            return count
        }
        if n % 120 == 0 { log.debug("stub received \(n) frames (\(w)x\(h))") }
        #endif
    }

    var connectionCount: Int {
        #if NDI_SDK_AVAILABLE
        return bridge.connectionCount()
        #else
        return 0
        #endif
    }

    func stop() {
        #if NDI_SDK_AVAILABLE
        bridge.stop()
        #endif
        log.info("NDI sender stopped: \(self.name, privacy: .public)")
    }
}
