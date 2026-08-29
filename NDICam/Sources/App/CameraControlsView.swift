import SwiftUI

struct CameraControlsView: View {
    @EnvironmentObject private var settings: BroadcastSettings
    @Environment(\.dismiss) private var dismiss
    let ranges: CameraControlRanges

    var body: some View {
        NavigationStack {
            Form {
                Section("Exposure") {
                    Picker("Mode", selection: Binding(
                        get: { settings.autoExposure },
                        set: { settings.autoExposure = $0 }
                    )) {
                        Text("Auto").tag(true)
                        Text("Manual").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !settings.autoExposure {
                        slider("ISO",
                               value: Binding(get: { settings.iso }, set: { settings.iso = $0 }),
                               range: ranges.minISO...max(ranges.minISO + 1, ranges.maxISO),
                               step: 1,
                               format: { "\(Int($0))" })

                        slider("Shutter",
                               value: Binding(
                                get: { Float(settings.shutterDenominator) },
                                set: { settings.shutterDenominator = Int($0) }),
                               range: Float(ranges.minShutterDenominator)...Float(max(ranges.minShutterDenominator + 1, ranges.maxShutterDenominator)),
                               step: 1,
                               format: { "1/\(Int($0))" })
                    }
                }

                Section("White balance") {
                    Picker("Mode", selection: Binding(
                        get: { settings.autoWhiteBalance },
                        set: { settings.autoWhiteBalance = $0 }
                    )) {
                        Text("Auto").tag(true)
                        Text("Manual").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !settings.autoWhiteBalance {
                        slider("Temperature",
                               value: Binding(get: { settings.whiteBalanceTemperature },
                                              set: { settings.whiteBalanceTemperature = $0 }),
                               range: 2500...9000, step: 50,
                               format: { "\(Int($0)) K" })

                        slider("Tint",
                               value: Binding(get: { settings.whiteBalanceTint },
                                              set: { settings.whiteBalanceTint = $0 }),
                               range: -150...150, step: 1,
                               format: { "\(Int($0))" })
                    }
                }

                Section {
                    Button("Reset to auto") {
                        settings.apply(CameraControlState())
                    }
                }
            }
            .navigationTitle("Camera")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func slider(_ title: String,
                        value: Binding<Float>,
                        range: ClosedRange<Float>,
                        step: Float,
                        format: @escaping (Float) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
