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

    deinit {
        pollingTask?.cancel()
    }

    public var engineName: String {
        engine.name
    }

    public var selectedTorrent: Torrent? {
        guard let selection else { return nil }
        return torrents.first { $0.id == selection }
    }

    public func addMagnet(_ magnet: String) {
        let magnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !magnet.isEmpty else { return }

        Task {
            do {
                let torrent = try await engine.addMagnet(magnet)
                upsert(torrent)
                selection = torrent.id
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    public func refresh() {
        Task {
            await refreshNow()
        }
    }

    public func refreshNow() async {
        do {
            torrents = try await engine.list()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
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
