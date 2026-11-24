import SwiftUI
import SweepCore

struct SettingsView: View {
    let updates: AppUpdates
    let network: MacNetworkSession

    var body: some View {
        let store = network.store
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
                            chooseDefaultLocation(store)
                        }
                    }
                }
            }
            Section("Network") {
                Toggle("Use direct Wi-Fi for torrents", isOn: Binding(
                    get: { network.directRequested }, set: network.selectDirect
                ))
                if network.directRequested {
                    Text("Trackers and peers see your Wi-Fi connection’s public IP. Requires a Wi-Fi network that gives Sweep an IPv4 address.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if network.needsApproval {
                    Button("Approve Wi-Fi Helper in System Settings…", action: network.openApproval)
                } else if network.mustRelaunch || network.directRequested != network.directAtLaunch {
                    Button("Relaunch Sweep to Apply", action: network.relaunch)
                }
                if let message = network.message { Text(message).foregroundStyle(.secondary) }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            network.refreshApproval()
        }
    }

    private func chooseDefaultLocation(_ store: TorrentStore) {
        guard let directory = chooseDownloadDirectory(initialPath: store.downloadDirectory) else {
            return
        }
        store.setDownloadDirectory(directory)
    }
}
