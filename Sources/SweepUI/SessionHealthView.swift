import SwiftUI
import SweepCore

public struct SessionHealthView: View {
    @Environment(TorrentStore.self) private var store
    private let showsTitle: Bool

    public init(showsTitle: Bool = true) { self.showsTitle = showsTitle }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle { Text("Session Health").font(.headline) }
            LabeledContent("Engine", value: store.engineName)
            LabeledContent("Session", value: store.isRestoringSession ? "Restoring" : "Loaded")
            LabeledContent("Pending", value: "\(store.pendingTorrentCount)")
            LabeledContent("Torrent errors", value: "\(store.torrents.filter { $0.error != nil }.count)")
            LabeledContent("Storage", value: store.hasPersistence ? (store.persistenceError == nil ? "Available" : "Save failed") : "Unavailable")
            if let updated = store.lastRefreshAt {
                LabeledContent("Last engine response") {
                    Text(updated, style: .relative)
                }
            } else {
                LabeledContent("Last engine response", value: "None")
            }
            if !errors.isEmpty {
                Divider()
                ForEach(errors, id: \.self) { error in
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            if let network = store.sessionStats.network {
                Divider()
                Text("Network · This Session").font(.headline)
                if let nodes = network.dhtNodesV4 {
                    LabeledContent("DHT", value: network.dhtStatus)
                    LabeledContent("DHT nodes", value: "\(nodes) IPv4 · \(network.dhtNodesV6 ?? 0) IPv6")
                    LabeledContent("DHT queries / replies", value: "\(network.dhtQueries) / \(network.dhtResponses)")
                    LabeledContent("DHT timeouts", value: "\(network.dhtTimeouts)")
                    LabeledContent("DHT requests in flight", value: "\(network.dhtOutstanding ?? 0)")
                    if let seconds = network.dhtLastResponseAgeSeconds {
                        LabeledContent("Last DHT reply", value: "\(seconds)s ago")
                    }
                    DisclosureGroup("DHT bootstrap") {
                        ForEach(network.dhtBootstrap, id: \.address) { bootstrap in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bootstrap.address).textSelection(.enabled)
                                Text("Addresses: \(bootstrap.resolvedAddresses) · Attempts: \(bootstrap.attempts)")
                                    .foregroundStyle(.secondary)
                                if let error = bootstrap.lastError {
                                    Text("Last error: \(error)").foregroundStyle(.orange).textSelection(.enabled)
                                }
                            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Bootstrap servers introduce other DHT nodes. Saved contacts are reused after relaunch and checked again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = network.dhtPersistenceError {
                        Text("Could not save DHT contacts: \(error)").foregroundStyle(.orange).textSelection(.enabled)
                    }
                } else {
                    LabeledContent("DHT", value: "Disabled")
                }
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Transport").gridColumnAlignment(.leading)
                        Text("Tried")
                        Text("Connected")
                        Text("Errors")
                    }.foregroundStyle(.secondary)
                    ForEach(network.transports, id: \.name) { transport in
                        GridRow {
                            Text(transport.name)
                            Text("\(transport.attempts)")
                            Text("\(transport.connected)")
                            Text("\(transport.failed)")
                        }
                    }
                }
                .font(.caption).monospacedDigit()
                LabeledContent("Live peers", value: "\(network.liveTCP) TCP · \(network.liveUTP) uTP")
                Text("Connected counts sockets before the BitTorrent handshake. Errors exclude cancelled attempts. DHT nodes are routing-table entries, not peers for this torrent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.lastError != nil {
                Button("Dismiss Action Error") { store.lastError = nil }
            }
            Text("A responding engine does not guarantee reachable peers. See the torrent inspector for transfer and tracker details.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var errors: [String] {
        [store.engineError, store.startupError, store.persistenceError, store.refreshError, store.lastError]
            .compactMap { $0 }
            .reduce(into: []) { result, error in
                if !result.contains(error) { result.append(error) }
            }
    }
}
