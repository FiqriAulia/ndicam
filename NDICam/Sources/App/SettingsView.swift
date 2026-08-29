import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: BroadcastSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("NDI source") {
                    TextField("Device name", text: Binding(
                        get: { settings.rawSourceName },
                        set: { settings.rawSourceName = $0 }
                    ), prompt: Text(settings.sourceName))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    Text("Shown on the network as \u{201C}\(settings.sourceName)\u{201D}. A change takes effect the next time you Start NDI.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Video") {
                    Picker("Resolution", selection: Binding(
                        get: { settings.resolution },
                        set: { settings.resolution = $0 }
                    )) {
                        ForEach(BroadcastSettings.Resolution.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Frame rate", selection: Binding(
                        get: { settings.frameRate },
                        set: { settings.frameRate = $0 }
                    )) {
                        ForEach(BroadcastSettings.FrameRate.allCases) { Text($0.label).tag($0) }
                    }
                    Text("1080p60 is the highest quality but uses the most WiFi bandwidth (full-bandwidth NDI, ~130 Mbps). Drop to 720p30 if the stream stutters.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
