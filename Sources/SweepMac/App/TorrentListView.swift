import AppKit
import SwiftUI
import SweepCore

struct TorrentListView: View {
    @EnvironmentObject private var store: TorrentStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Table(store.torrents, selection: $store.selection) {
                TableColumn("Name") { torrent in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(torrent.name)
                            .lineLimit(1)
                        Text(torrent.infoHash)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 260, ideal: 360)

                TableColumn("Progress") { torrent in
                    ProgressView(value: torrent.progress)
                        .progressViewStyle(.linear)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Status") { torrent in
                    Text(torrent.statusLabel)
                        .foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110)

                TableColumn("Down") { torrent in
                    Text(ByteFormatter.rate(torrent.downloadBps))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 90)

                TableColumn("Up") { torrent in
                    Text(ByteFormatter.rate(torrent.uploadBps))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 90)
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
                    revealSelectedTorrentInFinder()
                }
                .disabled(store.selectedTorrent == nil)

                Button("Show Inspector") {
                    openWindow(id: AppWindowID.torrentInspector)
                }

                Divider()

                Button("Remove") {
                    store.removeSelectedTorrent()
                }
                .disabled(store.selectedTorrent == nil)

                Button("Remove and Delete Data") {
                    store.removeSelectedTorrent(deleteData: true)
                }
                .disabled(store.selectedTorrent == nil)
            }
            .onDeleteCommand {
                store.removeSelectedTorrent()
            }

            InspectorBar(torrent: store.selectedTorrent)
        }
        .navigationTitle("Torrents")
    }

    private func revealSelectedTorrentInFinder() {
        guard let torrent = store.selectedTorrent else { return }
        TorrentFileLocation.revealInFinder(
            torrent: torrent,
            defaultDirectory: store.downloadDirectory
        )
    }
}

private struct InspectorBar: View {
    let torrent: Torrent?

    var body: some View {
        HStack(spacing: 16) {
            if let torrent {
                Label(ByteFormatter.bytes(torrent.progressBytes), systemImage: "arrow.down")
                Label(ByteFormatter.bytes(torrent.uploadedBytes), systemImage: "arrow.up")
                Label(ByteFormatter.bytes(torrent.totalBytes), systemImage: "externaldrive")
                Spacer()
                Text(torrent.statusLabel)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Torrent Selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.bar)
    }
}
