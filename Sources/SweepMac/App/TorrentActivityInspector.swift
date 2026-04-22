import SwiftUI
import SweepCore

struct TorrentActivityInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Progress") {
                VStack(alignment: .leading, spacing: 5) {
                    SegmentedProgressView(
                        runs: torrent.pieceRuns,
                        fallbackProgress: torrent.progress,
                        state: torrent.statusLabel,
                        height: 9
                    )
                    HStack {
                        Text(TorrentDisplayFormat.percent(torrent.progress))
                        Spacer()
                        Text(torrent.statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }

                InspectorRow("Downloaded", value: ByteFormatter.bytes(torrent.progressBytes))
                InspectorRow("Remaining", value: TorrentDisplayFormat.remainingBytes(torrent))
                InspectorRow("Total Size", value: TorrentDisplayFormat.bytesOrUnknown(torrent.totalBytes))
            }

            InspectorGroup("Transfer") {
                InspectorRow("Download", value: ByteFormatter.rate(torrent.downloadBps))
                InspectorRow("Upload", value: ByteFormatter.rate(torrent.uploadBps))
                InspectorRow("Uploaded", value: ByteFormatter.bytes(torrent.uploadedBytes))
                InspectorRow("Ratio", value: TorrentDisplayFormat.ratio(torrent))
                InspectorRow("ETA", value: torrent.etaSeconds.map(TorrentDisplayFormat.duration) ?? "Unknown")
            }

            InspectorGroup("State") {
                InspectorRow("Engine", value: torrent.state)
                InspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                InspectorRow("Last Update", value: TorrentDisplayFormat.date(torrent.updatedAt))
            }
        }
    }
}
