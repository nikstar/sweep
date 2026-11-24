import SwiftUI
import SweepCore

struct SettingsView: View {
    @Environment(TorrentStore.self) private var store
    let updates: AppUpdates

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Engine", value: store.engineName)

                LabeledContent("Default Location") {
                    HStack(spacing: 8) {
                        Text(abbreviatedPath(store.downloadDirectory))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Choose...") {
                            chooseDefaultLocation()
                        }
                    }
                }
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: updates.setAutomaticChecks
                ))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 500)
    }

    private func chooseDefaultLocation() {
        guard let directory = chooseDownloadDirectory(initialPath: store.downloadDirectory) else {
            return
        }
        store.setDownloadDirectory(directory)
    }
}
