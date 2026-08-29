import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: BroadcastSettings
    @Environment(\.dismiss) private var dismiss
    var remoteControlURL: String?

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

                Section("Remote control") {
                    Toggle("Web control panel", isOn: Binding(
                        get: { settings.remoteControlEnabled },
                        set: { settings.remoteControlEnabled = $0 }
                    ))
                    if settings.remoteControlEnabled {
                        if let url = remoteControlURL {
                            LabeledContent("Open in a browser") {
                                Text(url).textSelection(.enabled).foregroundStyle(.tint)
                            }
                            Text("Add this URL as an OBS custom browser dock to control the camera from your desktop. Same WiFi only.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Starting server…").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Off by default. When on, NDICam serves a small control page on your local network — nothing runs otherwise.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
