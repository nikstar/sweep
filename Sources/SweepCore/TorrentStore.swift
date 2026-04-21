import Foundation

@MainActor
public final class TorrentStore: ObservableObject {
    @Published public var torrents: [Torrent] = []
    @Published public var selection: Torrent.ID? {
        didSet {
            persistSelection()
        }
    }
    @Published public var showingAddSheet = false
    @Published public var lastError: String?
    @Published public var downloadDirectory: String

    private let engine: TorrentEngine
    private let persistence: AppPersistence?
    private var pollingTask: Task<Void, Never>?

    public init(
        engine: TorrentEngine,
        persistence: AppPersistence? = nil,
        downloadDirectory: String,
        initialError: String? = nil
    ) {
        self.engine = engine
        self.persistence = persistence
        self.downloadDirectory = downloadDirectory
        self.lastError = initialError
        Task {
            await loadPersistedState()
            await refreshNow()
        }
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
                let torrent = try await engine.addMagnet(magnet).withMagnet(magnet)
                upsert(torrent)
                try await persistence?.save(torrent: torrent)
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
            let liveTorrents = try await engine.list()
            for torrent in liveTorrents {
                upsert(torrent)
            }
            try await persistence?.save(torrents: torrents)
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
            torrents[index] = torrent.withMagnet(torrents[index].magnet)
        } else {
            torrents.append(torrent)
        }
    }

    private func loadPersistedState() async {
        do {
            guard let state = try await persistence?.loadState() else { return }
            if !state.torrents.isEmpty {
                torrents = state.torrents
            }
            if let downloadDirectory = state.downloadDirectory {
                self.downloadDirectory = downloadDirectory
            } else {
                try? await persistence?.saveSetting(.downloadDirectory, value: downloadDirectory)
            }
            selection = state.selectedTorrentID
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistSelection() {
        let selection = selection.map(String.init)
        Task {
            try? await persistence?.saveSetting(.selectedTorrentID, value: selection)
        }
    }
}
