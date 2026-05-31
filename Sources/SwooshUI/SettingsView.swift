import SwiftUI
import SwooshCore

/// The settings window (SPEC §5 bounded surface, §8). Grid dimensions + a tight option set —
/// deliberately no free-form config field (the declined config-DSL, STRATEGY §4.2).
public struct SettingsView: View {
    @ObservedObject private var model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Grid") {
                Stepper("Columns: \(model.settings.gridCols)",
                        value: $model.settings.gridCols, in: 1 ... SwooshSettings.maxGridDimension)
                Stepper("Rows: \(model.settings.gridRows)",
                        value: $model.settings.gridRows, in: 1 ... SwooshSettings.maxGridDimension)
                Text("Ultrawide layouts work natively — e.g. 5 columns × 1 row.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Feel") {
                Toggle("Haptic feedback", isOn: $model.settings.hapticsEnabled)
            }

            Section("Gaps") {
                Stepper("Outer margin: \(Int(model.settings.outerGap)) pt",
                        value: $model.settings.outerGap, in: 0 ... 40, step: 2)
                Stepper("Inner gutter: \(Int(model.settings.innerGap)) pt",
                        value: $model.settings.innerGap, in: 0 ... 40, step: 2)
            }

            Section("Gesture") {
                Slider(value: $model.settings.commitThreshold, in: 5 ... 100) {
                    Text("Swipe commit threshold")
                }
                Text("Higher = a longer swipe is needed before a snap commits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .onSubmit { model.normalize() }
    }
}
