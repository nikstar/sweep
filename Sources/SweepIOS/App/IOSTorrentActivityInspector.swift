import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentActivityInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            if let discovery = store.discoveries[torrent.id] {
                IOSInspectorGroup(discovery.isActive ? "Finding Metadata" : "Last Metadata Attempt") {
                    MetadataDiscoveryView(discovery: discovery)
                }
            }
            IOSInspectorGroup("Progress") {
                VStack(alignment: .leading, spacing: 5) {
                    SegmentedProgressView(
                        runs: torrent.pieceRuns,
                        fallbackProgress: torrent.progress,
                        state: torrent.statusLabel,
                        height: 10
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

                IOSInspectorRow("Downloaded", value: ByteFormatter.bytes(torrent.progressBytes))
                if let checking = torrent.checkingProgress {
                    IOSInspectorRow("Files Checked", value: TorrentDisplayFormat.percent(checking))
                    Text("Downloaded shows the last known payload progress until checking finishes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                IOSInspectorRow("Remaining", value: TorrentDisplayFormat.remainingBytes(torrent))
                IOSInspectorRow("Total Size", value: TorrentDisplayFormat.bytesOrUnknown(torrent.totalBytes))
            }

            IOSInspectorGroup("Transfer") {
                IOSInspectorRow("Download", value: ByteFormatter.rate(torrent.downloadBps))
                IOSInspectorRow("Upload", value: ByteFormatter.rate(torrent.uploadBps))
                IOSInspectorRow("Uploaded", value: ByteFormatter.bytes(torrent.uploadedBytes))
                IOSInspectorRow("Ratio", value: TorrentDisplayFormat.ratio(torrent))
                IOSInspectorRow("ETA", value: torrent.etaSeconds.map(TorrentDisplayFormat.duration) ?? "Unknown")
            }

            IOSInspectorGroup("State") {
                IOSInspectorRow("Engine", value: torrent.state)
                IOSInspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                IOSInspectorRow("Last Update", value: TorrentDisplayFormat.date(torrent.updatedAt))
            }
        }
    }
}
