import SwiftUI
import SweepCore

struct TorrentPeersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Summary") {
                let livePeers = torrent.peers.filter(\.isLiveConnection)
                InspectorMetricLine {
                    InspectorMetric("Live", String(livePeers.count))
                    InspectorMetric("Downloading", String(livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count))
                    InspectorMetric("Uploading", String(livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count))
                }
            }

            if torrent.peers.isEmpty {
                InspectorEmptyState("No connected peers")
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(torrent.peers) { peer in
                        TorrentPeerInspectorRow(peer: peer)
                    }
                }
            }
        }
    }
}

private struct TorrentPeerInspectorRow: View {
    let peer: TorrentPeer

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: peer.isLiveConnection ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(peer.isLiveConnection ? .green : .secondary)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(peer.address)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Text(TorrentDisplayFormat.peerConnection(peer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                InspectorTextLine {
                    Text(peer.client ?? peer.state.capitalized)
                    if let countryCode = peer.countryCode {
                        Text(countryCode)
                    }
                    if let availability = peer.availability {
                        Text("\(TorrentDisplayFormat.percent(availability)) available")
                    }
                    if let availablePieces = peer.availablePieces {
                        Text("\(availablePieces) pieces")
                    }
                }

                if let availability = peer.availability {
                    ProgressView(value: availability.clamped(to: 0...1))
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }

                InspectorTextLine {
                    Text("\(ByteFormatter.bytes(peer.downloadedBytes)) down")
                    Text("\(ByteFormatter.bytes(peer.uploadedBytes)) up")
                    if let downloadBps = peer.downloadBps {
                        Text("\(ByteFormatter.rate(downloadBps)) down")
                    }
                    if let uploadBps = peer.uploadBps {
                        Text("\(ByteFormatter.rate(uploadBps)) up")
                    }
                    if peer.errors > 0 {
                        Text("\(peer.errors) errors")
                            .foregroundStyle(.orange)
                    }
                }

                if !peer.featureFlags.isEmpty {
                    Text(peer.featureFlags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let peerID = peer.peerID {
                    Text(peerID)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
