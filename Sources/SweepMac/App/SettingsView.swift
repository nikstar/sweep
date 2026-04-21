import SwiftUI
import SweepCore

struct SettingsView: View {
    let engineName: String
    let downloadDirectory: String

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Engine", value: engineName)
                LabeledContent("Default Location", value: abbreviatedPath(downloadDirectory))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
