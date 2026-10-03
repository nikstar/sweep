import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentPeersInspector: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            if let discovery = store.discoveries[torrent.id] {
                IOSInspectorGroup(discovery.isActive ? "Finding Metadata" : "Last Metadata Attempt") {
                    MetadataDiscoveryView(discovery: discovery)
                }
            }
            IOSInspectorGroup("Summary") {
                let livePeers = torrent.peers.filter(\.isLiveConnection)
                IOSInspectorMetricLine {
                    IOSInspectorMetric("Live", String(livePeers.count))
                    IOSInspectorMetric("Downloading", String(livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count))
                    IOSInspectorMetric("Uploading", String(livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count))
                }
            }

            if torrent.peers.isEmpty {
                IOSInspectorEmptyState("No connected peers")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(torrent.peers) { peer in
                        IOSTorrentPeerRow(peer: peer)
                    }
                }
            }
        }
    }
}

private struct IOSTorrentPeerRow: View {
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

                IOSInspectorTextLine {
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

                IOSInspectorTextLine {
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
