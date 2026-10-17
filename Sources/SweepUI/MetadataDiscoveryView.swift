import SwiftUI
import SweepCore

public struct MetadataDiscoveryView: View {
    let discovery: TorrentDiscovery

    public init(discovery: TorrentDiscovery) { self.discovery = discovery }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if discovery.isActive, let seconds = discovery.retryInSeconds {
                Label("No metadata yet. Retrying in \(seconds)s", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Attempt", value: String(discovery.attempt))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                LabeledContent("Found", value: String(discovery.peersFound))
                LabeledContent("Tried", value: String(discovery.peersTried))
                LabeledContent("Active", value: String(discovery.peersActive))
                LabeledContent("Failed", value: String(discovery.peersFailed))
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text("Stage"); Text("Reached"); Text("Failed") }.foregroundStyle(.secondary)
                GridRow { Text("Socket"); Text("\(discovery.socketsConnected)"); Text("\(discovery.connectFailures)") }
                GridRow { Text("BitTorrent handshake"); Text("\(discovery.handshakesCompleted)"); Text("\(discovery.handshakeFailures)") }
                GridRow { Text("Metadata exchange"); Text("\(discovery.metadataPeers)"); Text("\(discovery.metadataFailures)") }
            }
            .font(.caption).monospacedDigit()
            LabeledContent("Metadata blocks", value: String(discovery.metadataBlocks))
            LabeledContent("Sources", value: "\(discovery.trackerCandidates) tracker · \(discovery.dhtCandidates) DHT · \(discovery.pexCandidates) PEX · \(discovery.otherCandidates) other")
            LabeledContent("Elapsed", value: "\(discovery.elapsedSeconds) seconds")
            Text("Counts describe this attempt. Sources can report the same address. Handshake failures include extension negotiation; finding an address does not mean it is reachable.")
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
