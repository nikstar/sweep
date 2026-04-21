import Foundation

@MainActor
public final class TorrentStore: ObservableObject {
    @Published public var torrents: [Torrent] = []
    @Published public var selection: Torrent.ID?
    @Published public var showingAddSheet = false
    @Published public var lastError: String?

    private let engine: TorrentEngine
    private var pollingTask: Task<Void, Never>?

    public init(engine: TorrentEngine) {
        self.engine = engine
        refresh()
    }

    public var engineName: String {
        engine.name
    }

    public var selectedTorrent: Torrent? {
        guard let selection else { return nil }
        return torrents.first { $0.id == selection }
    }

    public func addMagnet(_ magnet: String) {
        do {
            let torrent = try engine.addMagnet(magnet.trimmingCharacters(in: .whitespacesAndNewlines))
            upsert(torrent)
            selection = torrent.id
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refresh() {
        do {
            torrents = try engine.list()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    private func upsert(_ torrent: Torrent) {
        if let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
            torrents[index] = torrent
        } else {
            torrents.append(torrent)
        }
    }
}
