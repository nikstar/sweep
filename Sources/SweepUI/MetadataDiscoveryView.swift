import SwiftUI
import SweepCore

public struct MetadataDiscoveryView: View {
    let discovery: TorrentDiscovery

    public init(discovery: TorrentDiscovery) { self.discovery = discovery }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                LabeledContent("Found", value: String(discovery.peersFound))
                LabeledContent("Tried", value: String(discovery.peersTried))
                LabeledContent("Active", value: String(discovery.peersActive))
                LabeledContent("Failed", value: String(discovery.peersFailed))
            }
            LabeledContent("Elapsed", value: "\(discovery.elapsedSeconds) seconds")
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
