import SwiftUI
import SweepCore

struct TorrentActivityInspector: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            if let discovery = store.discoveries[torrent.id] {
                MetadataDiscoveryGroup(discovery: discovery)
            }
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

struct MetadataDiscoveryGroup: View {
    let discovery: TorrentDiscovery

    var body: some View {
        InspectorGroup(discovery.isActive ? "Finding Metadata" : "Last Metadata Attempt") {
            InspectorMetricLine {
                InspectorMetric("Found", String(discovery.peersFound))
                InspectorMetric("Tried", String(discovery.peersTried))
                InspectorMetric("Active", String(discovery.peersActive))
                InspectorMetric("Failed", String(discovery.peersFailed))
            }
            InspectorRow("Elapsed", value: "\(discovery.elapsedSeconds) seconds")
            Text("Peers found are candidates. A successful connection and metadata exchange are needed before downloading files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = discovery.lastPeerError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }
}
