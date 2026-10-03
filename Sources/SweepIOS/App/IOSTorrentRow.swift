import SwiftUI
import SweepCore
import SweepUI

struct IOSTorrentRow: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TorrentStatusIcon(torrent: torrent, fontSize: 14)
                .frame(width: 20, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(torrent.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Text(TorrentDisplayFormat.percent(torrent.progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                SegmentedProgressView(
                    runs: torrent.pieceRuns,
                    fallbackProgress: torrent.progress,
                    state: torrent.statusLabel,
                    height: 8
                )

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(torrent.error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 12) {
                    TransferMetric(systemImage: "arrow.down", value: ByteFormatter.rate(torrent.downloadBps), isActive: torrent.downloadBps > 1)
                    TransferMetric(systemImage: "arrow.up", value: ByteFormatter.rate(torrent.uploadBps), isActive: torrent.uploadBps > 1)
                    PeerMetric(torrent: torrent)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 5)
    }

    private var statusText: String {
        TorrentDisplayFormat.statusSummary(torrent, discovery: store.discoveries[torrent.id])
    }

}

private struct TransferMetric: View {
    let systemImage: String
    let value: String
    let isActive: Bool

    var body: some View {
        Label {
            Text(value)
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(isActive ? .primary : .secondary)
    }
}

private struct PeerMetric: View {
    let torrent: Torrent

    var body: some View {
        let livePeers = torrent.peers.filter(\.isLiveConnection)
        Label {
            Text("\(livePeers.count)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "person.2")
        }
        .foregroundStyle(livePeers.isEmpty ? .secondary : .primary)
    }
}
