import SwiftUI

/// User-configurable broadcast parameters, persisted in `UserDefaults`.
@MainActor
final class BroadcastSettings: ObservableObject {

    enum Resolution: Int, CaseIterable, Identifiable {
        case p720 = 720
        case p1080 = 1080
        var id: Int { rawValue }
        var label: String { "\(rawValue)p" }
        var dimensions: (width: Int32, height: Int32) {
            switch self {
            case .p720: return (1280, 720)
            case .p1080: return (1920, 1080)
            }
        }
    }

    enum FrameRate: Int, CaseIterable, Identifiable {
        case fps30 = 30
        case fps60 = 60
        var id: Int { rawValue }
        var label: String { "\(rawValue) fps" }
    }

    @AppStorage("broadcast.resolution") private var resolutionRaw = Resolution.p720.rawValue
    @AppStorage("broadcast.fps") private var fpsRaw = FrameRate.fps30.rawValue
    @AppStorage("broadcast.sourceName") private var storedSourceName = ""

    // Manual camera controls
    @AppStorage("cam.autoExposure") private var camAutoExposure = true
    @AppStorage("cam.iso") private var camISO = 100.0
    @AppStorage("cam.shutterDen") private var camShutterDen = 60
    @AppStorage("cam.autoWB") private var camAutoWB = true
    @AppStorage("cam.wbTemp") private var camWBTemp = 5000.0
    @AppStorage("cam.wbTint") private var camWBTint = 0.0

    /// Opt-in web remote-control server (off by default — zero cost when off).
    @AppStorage("remote.enabled") private var remoteEnabledRaw = false

    var resolution: Resolution {
        get { Resolution(rawValue: resolutionRaw) ?? .p720 }
        set { resolutionRaw = newValue.rawValue; objectWillChange.send() }
    }

    var frameRate: FrameRate {
        get { FrameRate(rawValue: fpsRaw) ?? .fps30 }
        set { fpsRaw = newValue.rawValue; objectWillChange.send() }
    }

    /// NDI source name. Falls back to the device name when the user hasn't set one.
    var sourceName: String {
        get {
            let trimmed = storedSourceName.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "\(UIDevice.current.name) (NDICam)" : trimmed
        }
        set { storedSourceName = newValue; objectWillChange.send() }
    }

    var rawSourceName: String {
        get { storedSourceName }
        set { storedSourceName = newValue; objectWillChange.send() }
    }

    var remoteControlEnabled: Bool {
        get { remoteEnabledRaw }
        set { remoteEnabledRaw = newValue; objectWillChange.send() }
    }

    // MARK: - Camera controls

    var autoExposure: Bool {
        get { camAutoExposure }
        set { camAutoExposure = newValue; objectWillChange.send() }
    }
    var iso: Float {
        get { Float(camISO) }
        set { camISO = Double(newValue); objectWillChange.send() }
    }
    var shutterDenominator: Int {
        get { camShutterDen }
        set { camShutterDen = newValue; objectWillChange.send() }
    }
    var autoWhiteBalance: Bool {
        get { camAutoWB }
        set { camAutoWB = newValue; objectWillChange.send() }
    }
    var whiteBalanceTemperature: Float {
        get { Float(camWBTemp) }
        set { camWBTemp = Double(newValue); objectWillChange.send() }
    }
    var whiteBalanceTint: Float {
        get { Float(camWBTint) }
        set { camWBTint = Double(newValue); objectWillChange.send() }
    }

    /// Immutable snapshot handed to the capture layer.
    var snapshot: CaptureConfig {
        let dims = resolution.dimensions
        return CaptureConfig(width: dims.width, height: dims.height,
                             fps: Int32(frameRate.rawValue), sourceName: sourceName)
    }

    var controlState: CameraControlState {
        CameraControlState(
            autoExposure: camAutoExposure,
            iso: Float(camISO),
            shutterDenominator: camShutterDen,
            autoWhiteBalance: camAutoWB,
            temperature: Float(camWBTemp),
            tint: Float(camWBTint)
        )
    }

    func apply(_ s: CameraControlState) {
        camAutoExposure = s.autoExposure
        camISO = Double(s.iso)
        camShutterDen = s.shutterDenominator
        camAutoWB = s.autoWhiteBalance
        camWBTemp = Double(s.temperature)
        camWBTint = Double(s.tint)
        objectWillChange.send()
    }
}

/// Plain value type consumed by `CaptureEngine` off the main actor.
struct CaptureConfig: Equatable, Sendable {
    var width: Int32
    var height: Int32
    var fps: Int32
    var sourceName: String
}
