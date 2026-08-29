import SwiftUI

struct ContentView: View {
    @StateObject private var camera: CameraCaptureController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showControls = false

    init(controller: CameraCaptureController) {
        _camera = StateObject(wrappedValue: controller)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .unauthorized:
                message("Camera access denied.\nEnable it in Settings › NDICam.")
            case .failed(let reason):
                message("Capture failed:\n\(reason)")
            case .idle, .running:
                CameraPreviewView(session: camera.session).ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                if camera.isBroadcasting {
                    Text("Keep NDICam open — iOS stops the camera when the app is in the background.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 32)
                        .padding(.bottom, 6)
                }
                bottomBar
            }
        }
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
            default: break
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(remoteControlURL: camera.remoteControlURL)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showControls) {
            CameraControlsView(ranges: camera.controlRanges)
                .presentationDetents([.medium, .large])
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            if camera.isBroadcasting {
                VStack(alignment: .leading, spacing: 4) {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.red, in: Capsule())
                    Text(camera.connectionCount == 0
                         ? "no receivers"
                         : "\(camera.connectionCount) receiver\(camera.connectionCount == 1 ? "" : "s")")
                        .font(.caption2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(camera.settings.sourceName).font(.caption2.bold())
                Text(camera.activeFormat).font(.caption2).opacity(0.7)
                if camera.thermalState == .serious || camera.thermalState == .critical {
                    Label("device hot", systemImage: "thermometer.high")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .foregroundStyle(.white)
        .padding()
    }

    private var bottomBar: some View {
        HStack(spacing: 22) {
            circleButton("camera.aperture") { showControls = true }
            circleButton("gearshape") { showSettings = true }
            Button {
                camera.toggleBroadcast()
            } label: {
                Text(camera.isBroadcasting ? "Stop NDI" : "Start NDI")
                    .font(.headline)
                    .frame(width: 132, height: 56)
                    .background(camera.isBroadcasting ? .red : .green, in: Capsule())
                    .foregroundStyle(.white)
            }
            circleButton("arrow.triangle.2.circlepath.camera") { camera.switchCamera() }
        }
        .padding(.bottom, 28)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding()
    }
}
