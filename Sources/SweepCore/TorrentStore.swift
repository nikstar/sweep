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
    private var launchTask: Task<Void, Never>?

    public init(
        engine: TorrentEngine,
        persistence: AppPersistence? = nil,
        downloadDirectory: String,
        initialState: PersistedAppState? = nil,
        initialError: String? = nil
    ) {
        self.engine = engine
        self.persistence = persistence
        self.downloadDirectory = initialState?.downloadDirectory ?? downloadDirectory
        self.lastError = initialError
        if let initialState {
            self.torrents = normalized(torrents: initialState.torrents, downloadDirectory: self.downloadDirectory)
            self.selection = initialState.selectedTorrentID
        }
        launchTask = Task { [weak self] in
            await self?.prepareForLaunch(hasInitialState: initialState != nil)
        }
    }

    deinit {
        pollingTask?.cancel()
        launchTask?.cancel()
    }

    public var engineName: String {
        engine.name
    }

    public var selectedTorrent: Torrent? {
        guard let selection else { return nil }
        return torrents.first { $0.id == selection }
    }

    public var canPauseSelectedTorrent: Bool {
        selectedTorrent?.desiredState == .running
    }

    public var canResumeSelectedTorrent: Bool {
        selectedTorrent?.desiredState == .paused
    }

    public func addMagnet(_ magnet: String) {
        let magnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !magnet.isEmpty else { return }

        Task {
            do {
                let torrent = try await engine
                    .addMagnet(magnet, startPaused: false)
                    .updating(
                        magnet: magnet,
                        downloadDirectory: downloadDirectory,
                        desiredState: .running
                    )
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
                upsert(liveTorrent: torrent)
            }
            try await enforceDesiredStates(for: Set(liveTorrents.map(\.id)))
            try await persistence?.save(torrents: torrents)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func pauseSelectedTorrent() {
        guard let torrent = selectedTorrent else { return }
        Task {
            await pause(torrent)
        }
    }

    public func resumeSelectedTorrent() {
        guard let torrent = selectedTorrent else { return }
        Task {
            await resume(torrent)
        }
    }

    public func removeSelectedTorrent(deleteData: Bool = false) {
        guard let torrent = selectedTorrent else { return }
        Task {
            await remove(torrent, deleteData: deleteData)
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
        torrents.sort { $0.addedAt < $1.addedAt }
    }

    private func upsert(liveTorrent torrent: Torrent) {
        if let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
            torrents[index] = torrent
                .updating(downloadDirectory: downloadDirectory)
                .mergingCachedMetadata(from: torrents[index])
        } else {
            torrents.append(torrent.updating(downloadDirectory: downloadDirectory))
        }
        torrents.sort { $0.addedAt < $1.addedAt }
    }

    private func prepareForLaunch(hasInitialState: Bool) async {
        if !hasInitialState {
            await loadPersistedState()
        }
        await reconcileWithEngine()
    }

    private func loadPersistedState() async {
        do {
            guard let state = try await persistence?.loadState() else { return }
            if let downloadDirectory = state.downloadDirectory {
                self.downloadDirectory = downloadDirectory
            } else {
                try? await persistence?.saveSetting(.downloadDirectory, value: downloadDirectory)
            }
            if !state.torrents.isEmpty {
                torrents = normalized(torrents: state.torrents, downloadDirectory: self.downloadDirectory)
            }
            selection = state.selectedTorrentID
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reconcileWithEngine() async {
        do {
            let cachedTorrents = torrents
            let liveTorrents = try await engine.list()
            for torrent in liveTorrents {
                upsert(liveTorrent: torrent)
            }

            let liveTorrentIDs = Set(liveTorrents.map(\.id))
            let missingCachedTorrents = cachedTorrents.filter { torrent in
                !liveTorrentIDs.contains(torrent.id) && torrent.magnet != nil
            }

            for cachedTorrent in missingCachedTorrents {
                guard let magnet = cachedTorrent.magnet else { continue }
                do {
                    let restoredTorrent = try await engine
                        .addMagnet(magnet, startPaused: cachedTorrent.desiredState == .paused)
                        .mergingCachedMetadata(from: cachedTorrent)
                    upsert(restoredTorrent)
                } catch {
                    upsert(
                        cachedTorrent.updating(
                            state: cachedTorrent.desiredState == .paused ? "paused" : "missing",
                            downloadBps: 0,
                            uploadBps: 0,
                            error: error.localizedDescription
                        )
                    )
                }
            }

            let reconciledLiveTorrents = try await engine.list()
            for torrent in reconciledLiveTorrents {
                upsert(liveTorrent: torrent)
            }
            try await enforceDesiredStates(for: Set(reconciledLiveTorrents.map(\.id)))
            try await persistence?.save(torrents: torrents)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func enforceDesiredStates(for liveTorrentIDs: Set<Torrent.ID>) async throws {
        let torrentsToCheck = torrents.filter { liveTorrentIDs.contains($0.id) }
        for torrent in torrentsToCheck {
            switch (torrent.desiredState, torrent.isPausedInEngine) {
            case (.paused, false):
                let liveTorrent = try await engine.pause(id: torrent.id)
                    .mergingCachedMetadata(from: torrent)
                    .updating(desiredState: .paused)
                upsert(liveTorrent)
                try await persistence?.save(torrent: liveTorrent)

            case (.running, true):
                let liveTorrent = try await engine.resume(id: torrent.id)
                    .mergingCachedMetadata(from: torrent)
                    .updating(desiredState: .running)
                upsert(liveTorrent)
                try await persistence?.save(torrent: liveTorrent)

            case (.paused, true), (.running, false):
                break
            }
        }
    }

    private func pause(_ torrent: Torrent) async {
        let pausedTorrent = torrent.updating(
            desiredState: .paused,
            state: "paused",
            downloadBps: 0,
            uploadBps: 0
        )
        upsert(pausedTorrent)
        try? await persistence?.save(torrent: pausedTorrent)

        do {
            let liveTorrent = try await engine.pause(id: torrent.id)
                .mergingCachedMetadata(from: pausedTorrent)
                .updating(desiredState: .paused)
            upsert(liveTorrent)
            try await persistence?.save(torrent: liveTorrent)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resume(_ torrent: Torrent) async {
        let resumedTorrent = torrent.updating(desiredState: .running, state: "live")
        upsert(resumedTorrent)
        try? await persistence?.save(torrent: resumedTorrent)

        do {
            let liveTorrent = try await engine.resume(id: torrent.id)
                .mergingCachedMetadata(from: resumedTorrent)
                .updating(desiredState: .running)
            upsert(liveTorrent)
            try await persistence?.save(torrent: liveTorrent)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func remove(_ torrent: Torrent, deleteData: Bool) async {
        do {
            try await engine.remove(id: torrent.id, deleteData: deleteData)
            torrents.removeAll { $0.id == torrent.id }
            if selection == torrent.id {
                selection = torrents.first?.id
            }
            try await persistence?.deleteTorrent(id: torrent.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistSelection() {
        let selection = selection
        Task {
            try? await persistence?.saveSetting(.selectedTorrentID, value: selection)
        }
    }

    private func normalized(torrents: [Torrent], downloadDirectory: String) -> [Torrent] {
        torrents
            .map { torrent in
                if torrent.downloadDirectory == nil || torrent.downloadDirectory?.isEmpty == true {
                    return torrent.updating(downloadDirectory: downloadDirectory)
                }
                return torrent
            }
            .sorted { $0.addedAt < $1.addedAt }
    }
}
