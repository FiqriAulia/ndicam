import Foundation

/// Manual camera parameters. `Equatable`/`Sendable` value type so it can cross
/// the main actor → capture-queue boundary and be diffed cheaply.
///
/// Basic set today: exposure (ISO + shutter) and white balance, each with an
/// auto/lock switch. The PRO seam below lists what plugs in next without changing
/// this contract.
struct CameraControlState: Equatable, Sendable, Codable {
    var autoExposure = true
    var iso: Float = 100                // used when autoExposure == false
    var shutterDenominator: Int = 60    // 1/x second, used when autoExposure == false

    var autoWhiteBalance = true
    var temperature: Float = 5000       // Kelvin, used when autoWhiteBalance == false
    var tint: Float = 0                 // -150…150, used when autoWhiteBalance == false

    // PRO (future — drive through the same CameraControlling protocol):
    //   var focus: FocusMode           // .auto | .locked(lensPosition:) | .point(CGPoint)
    //   var zoomFactor: Float
    //   var lens: Lens                 // .ultraWide | .wide | .tele
    //   var stabilization: Mode        // .off | .standard | .cinematic
    //   var evBias: Float
    //   var colorSpace: ColorSpace     // .sRGB | .p3 | .hlg
}

/// Device-reported limits for the current `activeFormat`, so the UI (and any
/// remote driver) can bound its sliders.
struct CameraControlRanges: Equatable, Sendable, Codable {
    var minISO: Float = 30
    var maxISO: Float = 2000
    var minShutterDenominator: Int = 8     // longest exposure
    var maxShutterDenominator: Int = 8000  // shortest exposure
    var minTemperature: Float = 3000
    var maxTemperature: Float = 8000
}

/// The single surface every controller talks to — the on-device UI today, an
/// opt-in web dock or an NDI-metadata listener later. Nothing here knows about
/// SwiftUI or the transport.
protocol CameraControlling: AnyObject, Sendable {
    func applyCameraControls(_ state: CameraControlState)
    var cameraControlRanges: CameraControlRanges { get }
}
