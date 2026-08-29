import SwiftUI

@main
struct NDICamApp: App {
    @StateObject private var settings = BroadcastSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: CameraCaptureController(settings: settings))
                .environmentObject(settings)
                .statusBarHidden()
        }
    }
}
