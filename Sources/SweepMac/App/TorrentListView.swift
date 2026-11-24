import AppKit
import SwiftUI
import SweepCore
import SweepUI

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TorrentInspectorPanelPresenter.self) private var inspectorPanelPresenter
    @SceneStorage("Sweep.TorrentList.columnCustomization")
    private var columnCustomization = TableColumnCustomization<Torrent>()
    @SceneStorage("Sweep.TorrentList.progressColumnMode")
    private var progressColumnModeRaw = ProgressColumnMode.detailed.rawValue

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            Table(
                store.torrents,
                selection: $store.selection,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Name") { torrent in
                    TorrentNameCell(
                        torrent: torrent,
                        isSelected: store.selection == torrent.id
                    )
                }
                .width(min: 320, ideal: 420)
                .customizationID("name")
                .disabledCustomizationBehavior(.visibility)

                TableColumn("Progress") { torrent in
                    TorrentProgressCell(
                        torrent: torrent,
                        isSelected: store.selection == torrent.id,
                        mode: progressColumnMode,
                        onOptionClick: toggleProgressColumnMode
                    )
                }
                .width(min: 140, ideal: 170)
                .customizationID("progress")
                .disabledCustomizationBehavior(.visibility)

                TableColumn("Size") { torrent in
                    Text(ByteFormatter.bytes(torrent.totalBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)
                .customizationID("size")

                TableColumn("ETA") { torrent in
                    Text(TorrentDisplayFormat.eta(torrent))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90)
                .customizationID("eta")
                .defaultVisibility(.hidden)

                TableColumn("%") { torrent in
                    Text(TorrentDisplayFormat.percent(torrent.progress))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 64)
                .customizationID("percent")

                TableColumn("Remaining") { torrent in
                    Text(ByteFormatter.bytes(torrent.remainingBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 92, ideal: 112)
                .customizationID("remaining")

                TableColumn("Speed") { torrent in
                    VStack(alignment: .leading, spacing: 2) {
                        TransferRateLine(systemImage: "arrow.down", value: torrent.downloadBps)
                        TransferRateLine(systemImage: "arrow.up", value: torrent.uploadBps)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 92, ideal: 112)
                .customizationID("speed")

                TableColumn("Peers") { torrent in
                    PeerColumnCell(torrent: torrent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 86, ideal: 104)
                .customizationID("peers")
            }
            .contextMenu {
                Button("Resume") {
                    store.resumeSelectedTorrent()
                }
                .disabled(!store.canResumeSelectedTorrent)

                Button("Pause") {
                    store.pauseSelectedTorrent()
                }
                .disabled(!store.canPauseSelectedTorrent)

                Divider()

                Button("Reveal in Finder") {
                    TorrentActions.revealSelectedTorrent(in: store)
                }
                .disabled(store.selectedTorrent == nil)

                Button("Show Inspector") {
                    inspectorPanelPresenter.show(store: store)
                }
                .disabled(store.selectedTorrent == nil)

                Divider()

                Button("Remove") {
                    TorrentActions.remove(store.selectedTorrent, in: store)
                }
                .disabled(store.selectedTorrent == nil)

                Button("Remove and Delete Data") {
                    TorrentActions.remove(store.selectedTorrent, in: store, deleteData: true)
                }
                .disabled(store.selectedTorrent == nil)
            }
            .onDeleteCommand {
                TorrentActions.remove(store.selectedTorrent, in: store)
            }

            TransferStatusBar()
        }
    }

    private var progressColumnMode: ProgressColumnMode {
        ProgressColumnMode(rawValue: progressColumnModeRaw) ?? .detailed
    }

    private func toggleProgressColumnMode() {
        progressColumnModeRaw = progressColumnMode == .detailed
            ? ProgressColumnMode.barOnly.rawValue
            : ProgressColumnMode.detailed.rawValue
    }
}

private enum ProgressColumnMode: String {
    case detailed
    case barOnly
}

private struct PeerColumnCell: View {
    let torrent: Torrent

    var body: some View {
        let summary = PeerColumnSummary(torrent: torrent)
        VStack(alignment: .leading, spacing: 2) {
            PeerCountLine(
                systemImage: "arrow.down",
                active: summary.activeDownloading,
                total: summary.totalDownloadPeers,
                help: "Downloading from \(summary.activeDownloading) of \(summary.totalDownloadPeers) peers"
            )
            PeerCountLine(
                systemImage: "arrow.up",
                active: summary.activeUploading,
                total: summary.totalUploadPeers,
                help: "Uploading to \(summary.activeUploading) of \(summary.totalUploadPeers) peers"
            )
        }
    }
}

private struct PeerCountLine: View {
    let systemImage: String
    let active: Int
    let total: Int
    let help: String

    var body: some View {
        Label {
            Text("\(active) of \(total)")
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

private struct PeerColumnSummary {
    let activeDownloading: Int
    let activeUploading: Int
    let totalDownloadPeers: Int
    let totalUploadPeers: Int

    init(torrent: Torrent) {
        let livePeers = torrent.peers.filter(\.isLiveConnection)
        self.activeDownloading = livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count
        self.activeUploading = livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count
        self.totalDownloadPeers = livePeers.count
        self.totalUploadPeers = livePeers.count
    }
}

private struct TorrentNameCell: View {
    @Environment(TorrentStore.self) private var store
    @State private var isHovering = false

    let torrent: Torrent
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TorrentStatusIcon(torrent: torrent, isSelected: isSelected)
                .frame(width: 16, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(torrent.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
                        Button {
                            TorrentActions.togglePause(torrent, in: store)
                        } label: {
                            Image(systemName: torrent.transferActionSymbol)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(torrent.transferActionTitle)

                        Button {
                            TorrentActions.reveal(torrent, in: store)
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .opacity(isHovering || store.selection == torrent.id ? 1 : 0.72)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(torrent.error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(statusText)
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
    }

    private var statusText: String {
        TorrentDisplayFormat.statusSummary(torrent, discovery: store.discoveries[torrent.id], includingTransferRates: true)
    }

}

private struct TorrentProgressCell: View {
    let torrent: Torrent
    let isSelected: Bool
    let mode: ProgressColumnMode
    let onOptionClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SegmentedProgressView(
                runs: torrent.pieceRuns,
                fallbackProgress: torrent.progress,
                state: torrent.statusLabel,
                isSelected: isSelected,
                height: mode == .barOnly ? 16 : 8
            )
            if mode == .detailed {
                HStack(spacing: 4) {
                    Text(TorrentDisplayFormat.percent(torrent.progress))
                    if torrent.remainingBytes > 0 {
                        Text(ByteFormatter.bytes(torrent.remainingBytes))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if NSEvent.modifierFlags.contains(.option) {
                onOptionClick()
            }
        })
    }
}

private struct TransferRateLine: View {
    let systemImage: String
    let value: Double

    var body: some View {
        Label {
            Text(ByteFormatter.rate(value))
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(value > 1 ? .primary : .secondary)
    }
}

private struct TransferStatusBar: View {
    @Environment(TorrentStore.self) private var store
    @Environment(MacNetworkSession.self) private var network
    @State private var showingHealth = false
    private var needsAttention: Bool {
        store.healthError != nil || store.torrents.contains { $0.error != nil }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                showingHealth.toggle()
            } label: {
                Label(store.engineName, systemImage: needsAttention ? "exclamationmark.triangle" : (store.isWaitingForEngine ? "clock" : "checkmark.circle"))
                    .foregroundStyle(needsAttention ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Session health and restoration status")
            .popover(isPresented: $showingHealth) {
                SessionHealthView()
                    .padding(16)
                    .frame(width: 380)
                    .environment(store)
            }
            Label(ByteFormatter.rate(store.sessionStats.downloadBps), systemImage: "arrow.down")
            Label(ByteFormatter.rate(store.sessionStats.uploadBps), systemImage: "arrow.up")
            Label("\(store.sessionStats.livePeers) peers", systemImage: "person.2")

            if store.sessionStats.connectingPeers > 0 {
                Text("\(store.sessionStats.connectingPeers) connecting")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isWaitingForEngine {
                DirectWiFiStatus(network: network)
            } else if let error = store.healthError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(error)
            } else if store.isRestoringSession {
                Text("Restoring session…")
                    .foregroundStyle(.secondary)
            } else if store.pendingTorrentCount > 0 {
                Text("\(store.pendingTorrentCount) pending")
                    .foregroundStyle(.secondary)
            } else if let torrent = store.selectedTorrent {
                Text(torrent.statusLabel)
                    .foregroundStyle(.secondary)
            }

        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }
}

private struct DirectWiFiStatus: View {
    let network: MacNetworkSession

    var body: some View {
        HStack(spacing: 6) {
            if network.mustRelaunch || !network.directRequested {
                Text("Transfers are waiting.")
                Button("Relaunch Sweep", action: network.relaunch)
            } else if network.needsApproval {
                Text("Direct Wi-Fi needs approval.")
                Button("Open System Settings…", action: network.openApproval)
            } else if !network.connecting, let reason = network.message {
                Text("Direct Wi-Fi unavailable. Transfers are waiting.")
                    .help(reason)
                    .accessibilityHint(reason)
                Button("Retry", action: network.start)
            } else {
                Text("Connecting to direct Wi-Fi…")
            }
        }
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .task(id: network.needsApproval) {
            while network.needsApproval {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                network.refreshApproval()
            }
        }
        .onChange(of: network.needsApproval) { wasNeeded, isNeeded in
            if wasNeeded && !isNeeded { network.start() }
        }
    }
}
