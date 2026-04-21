import SwiftUI
import SweepCore

struct SettingsView: View {
    let engineName: String

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Engine", value: engineName)
                LabeledContent("Default Location", value: "~/Downloads/Sweep")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
