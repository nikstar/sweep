import Foundation
import Observation

@MainActor
@Observable
public final class TorrentStore {
    public var torrents: [Torrent] = []
    public var selection: Torrent.ID? {
        didSet {
            persistSelection()
        }
    }
    public var showingAddSheet = false
    public var pendingAddSource: TorrentAddSource?
    public var lastError: String?
    public var downloadDirectory: String
    public var sessionStats: TorrentSessionStats = .empty
    public private(set) var isRestoringSession = true
    public private(set) var lastRefreshAt: Date?
    public private(set) var refreshError: String?
    public private(set) var persistenceError: String?
    public private(set) var discoveries: [Torrent.ID: TorrentDiscovery] = [:]
    public let startupError: String?
    public var engineError: String? { engine.unavailabilityReason }
    public var hasPersistence: Bool { persistence != nil }
    public var pendingTorrentCount: Int { pendingAdds.count }

    public var healthError: String? {
        engineError ?? startupError ?? persistenceError ?? refreshError ?? lastError
    }

    private let engine: TorrentEngine
    private let persistence: AppPersistence?
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var launchTask: Task<Void, Never>?
    @ObservationIgnored
    private var locallyRemovedTorrentIDs: Set<Torrent.ID> = []
    @ObservationIgnored private var managedTorrentIDs: Set<Torrent.ID> = []
    private var pendingAdds: [Torrent.ID: UUID] = [:]
    @ObservationIgnored private var addTasks: [Torrent.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var mutationRevision = 0
    @ObservationIgnored private var commandVersions: [Torrent.ID: UUID] = [:]

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
        self.startupError = initialError
        if let initialState {
            self.torrents = normalized(torrents: initialState.torrents, downloadDirectory: self.downloadDirectory).map {
                $0.updating(state: $0.desiredState == .paused ? "paused" : "restoring", peers: [], pieceRuns: [], downloadBps: 0, uploadBps: 0, clearError: true)
            }
            self.selection = initialState.selectedTorrentID
        }
        launchTask = Task { [weak self] in
            await self?.prepareForLaunch(hasInitialState: initialState != nil)
        }
    }

    deinit {
        pollingTask?.cancel()
        launchTask?.cancel()
        for task in addTasks.values { task.cancel() }
    }

    public var engineName: String {
        engine.name
    }

    public var selectedTorrent: Torrent? {
        guard let selection else { return nil }
        return torrents.first { $0.id == selection }
    }

    public var canPauseSelectedTorrent: Bool {
        selectedTorrent?.desiredState == .running && engineError == nil
    }

    public var canResumeSelectedTorrent: Bool {
        guard let torrent = selectedTorrent, engineError == nil else { return false }
        return torrent.desiredState == .paused || torrent.error != nil
    }

    public func togglePause(_ torrent: Torrent) {
        selection = torrent.id
        if torrent.canResume {
            resumeSelectedTorrent()
        } else {
            pauseSelectedTorrent()
        }
    }

    public func beginAddingMagnet(_ magnet: String = "") {
        pendingAddSource = .magnet(magnet)
        showingAddSheet = true
    }

    public func beginAddingTorrentFile(_ file: TorrentFileSource) {
        pendingAddSource = .torrentFile(file)
        showingAddSheet = true
    }

    public func beginAddingTorrentFile(at url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            beginAddingTorrentFile(try TorrentFileSource(contentsOf: url))
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func beginAdding(url: URL) {
        if url.isFileURL {
            beginAddingTorrentFile(at: url)
            return
        }

        if url.scheme?.lowercased() == "magnet" {
            beginAddingMagnet(url.absoluteString)
            return
        }

        lastError = "Sweep can open magnet links and .torrent files."
    }

    @discardableResult
    public func addTorrent(
        _ source: TorrentAddSource,
        downloadDirectory: String,
        startPaused: Bool
    ) async -> Torrent? {
        await launchTask?.value
        if let engineError {
            lastError = engineError
            return nil
        }
        do {
            try createDownloadDirectory(at: downloadDirectory)
            if case .magnet(let value) = source {
                let magnet = try MagnetLink(value)
                if let existing = torrents.first(where: { $0.id == magnet.infoHash }) {
                    selection = existing.id
                    return existing
                }
                let torrent = Torrent(
                    name: magnet.name, infoHash: magnet.infoHash, magnet: magnet.value,
                    downloadDirectory: downloadDirectory,
                    desiredState: startPaused ? .paused : .running,
                    state: startPaused ? "paused" : "resolving", trackers: magnet.trackers,
                    progressBytes: 0, totalBytes: 0, uploadedBytes: 0,
                    downloadBps: 0, uploadBps: 0, error: nil
                )
                // Save the user's intent before starting any network work.
                try await persistence?.save(torrent: torrent)
                mutationRevision += 1
                locallyRemovedTorrentIDs.remove(torrent.id)
                upsert(torrent)
                selection = torrent.id
                if !startPaused { startAddingToEngine(torrent) }
                lastError = nil
                return torrent
            }
            mutationRevision += 1
            let torrent = try await engine
                .addTorrent(source, downloadDirectory: downloadDirectory, startPaused: startPaused)
                .withAddSource(source)
                .updating(
                    downloadDirectory: downloadDirectory,
                    desiredState: startPaused ? .paused : .running
                )
            locallyRemovedTorrentIDs.remove(torrent.id)
            managedTorrentIDs.insert(torrent.id)
            mutationRevision += 1
            upsert(torrent)
            try await persistence?.save(torrent: torrent)
            selection = torrent.id
            lastError = nil
            return torrent
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    public func setDownloadDirectory(_ downloadDirectory: String) {
        let downloadDirectory = (downloadDirectory as NSString).expandingTildeInPath
        do {
            try createDownloadDirectory(at: downloadDirectory)
            self.downloadDirectory = downloadDirectory
            Task {
                try? await persistence?.saveSetting(.downloadDirectory, value: downloadDirectory)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refresh() {
        Task {
            await refreshNow()
        }
    }

    public func refreshNow() async {
        await launchTask?.value
        guard !isRefreshing, engineError == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let revision = mutationRevision
        do {
            let liveTorrents = try await engine.list()
            let stats = try await engine.sessionStats()
            let discoverySnapshots = try await engine.discoverySnapshots()
            guard revision == mutationRevision else { return }
            updateDiscoveries(discoverySnapshots)
            managedTorrentIDs = Set(liveTorrents.map(\.id))
            let visibleLiveTorrents = filterVisibleLiveTorrents(from: liveTorrents)
            for torrent in visibleLiveTorrents where commandVersions[torrent.id] == nil
                && (pendingAdds[torrent.id] == nil || torrent.state == "initializing") {
                upsert(liveTorrent: torrent)
            }
            sessionStats = stats.smoothed(from: sessionStats)
            lastRefreshAt = Date()
            refreshError = nil
            try await enforceDesiredStates(for: Set(visibleLiveTorrents.map(\.id)))
            discardLocallyRemovedTorrents()
            // A removed pending add may finish just as cancellation arrives. It was
            // added paused, so clean up the handle without touching payload files.
            for torrent in liveTorrents where locallyRemovedTorrentIDs.contains(torrent.id) {
                try await engine.remove(id: torrent.id, deleteData: false)
            }
            await saveCurrentTorrents()
        } catch {
            refreshError = error.localizedDescription
            sessionStats = .empty
            torrents = torrents.map { $0.updating(downloadBps: 0, uploadBps: 0) }
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

    public func setFile(_ file: TorrentFile, included: Bool, in torrent: Torrent) {
        Task {
            await setFileSelection(file: file, included: included, in: torrent)
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
        guard !locallyRemovedTorrentIDs.contains(torrent.id) else { return }

        if let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
            torrents[index] = torrent
        } else {
            torrents.append(torrent)
        }
        torrents.sort { $0.addedAt < $1.addedAt }
    }

    private func upsert(liveTorrent torrent: Torrent) {
        guard !locallyRemovedTorrentIDs.contains(torrent.id) else { return }

        if let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
            let cached = torrents[index]
            torrents[index] = torrent
                .mergingCachedMetadata(from: cached)
                .withSmoothedTransferStats(from: cached)
                .withEstimatedPeerRates(from: cached)
        } else {
            torrents.append(torrent.updating(downloadDirectory: downloadDirectory))
        }
        torrents.sort { $0.addedAt < $1.addedAt }
    }

    private func prepareForLaunch(hasInitialState: Bool) async {
        defer { isRestoringSession = false }
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
                torrents = normalized(torrents: state.torrents, downloadDirectory: self.downloadDirectory).map {
                    $0.updating(state: $0.desiredState == .paused ? "paused" : "restoring", peers: [], pieceRuns: [], downloadBps: 0, uploadBps: 0, clearError: true)
                }
            }
            selection = state.selectedTorrentID
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reconcileWithEngine() async {
        guard engineError == nil else { return }
        do {
            let liveTorrents = try await engine.list()
            managedTorrentIDs = Set(liveTorrents.map(\.id))
            for torrent in filterVisibleLiveTorrents(from: liveTorrents) {
                upsert(liveTorrent: torrent)
            }
            for torrent in torrents where !managedTorrentIDs.contains(torrent.id) {
                if torrent.addSource == nil {
                    upsert(torrent.updating(state: "missing", error: "The saved torrent has no source. Add its magnet or torrent file again."))
                } else if torrent.desiredState == .running {
                    // Independent tasks prevent one unreachable magnet from blocking
                    // restoration of every other torrent.
                    startAddingToEngine(torrent)
                }
            }
            sessionStats = try await engine.sessionStats()
            lastRefreshAt = Date()
            refreshError = nil
            try await enforceDesiredStates(for: managedTorrentIDs)
            await saveCurrentTorrents()
        } catch {
            refreshError = error.localizedDescription
        }
    }

    private func startAddingToEngine(_ torrent: Torrent) {
        guard pendingAdds[torrent.id] == nil, engineError == nil else { return }
        let token = UUID()
        pendingAdds[torrent.id] = token
        discoveries.removeValue(forKey: torrent.id)
        mutationRevision += 1
        upsert(torrent.updating(
            state: torrent.torrentFileBytes == nil && torrent.magnet != nil ? "resolving" : "restoring",
            downloadBps: 0, uploadBps: 0, clearError: true
        ))
        addTasks[torrent.id] = Task { [weak self] in
            await self?.addToEngine(id: torrent.id, token: token)
        }
    }

    private func addToEngine(id: Torrent.ID, token: UUID) async {
        defer {
            if pendingAdds[id] == token {
                pendingAdds.removeValue(forKey: id)
                addTasks.removeValue(forKey: id)
            }
            mutationRevision += 1
        }
        guard !Task.isCancelled,
              let cached = torrents.first(where: { $0.id == id }),
              let source = cached.addSource else { return }
        do {
            // Start paused so file selection and the latest intent can be applied
            // before any payload download begins.
            var restored = try await engine.addTorrent(
                source,
                downloadDirectory: cached.downloadDirectory ?? downloadDirectory,
                startPaused: true
            )
            guard pendingAdds[id] == token, !Task.isCancelled else {
                if locallyRemovedTorrentIDs.contains(id) {
                    try? await engine.remove(id: id, deleteData: false)
                }
                return
            }
            managedTorrentIDs.insert(id)
            guard var current = torrents.first(where: { $0.id == id }) else { return }
            restored = restored.mergingCachedMetadata(from: current)
            if let file = try await engine.torrentFile(id: id) {
                current = current.withAddSource(.torrentFile(file))
                restored = restored.mergingCachedMetadata(from: current)
            }
            guard pendingAdds[id] == token else { return }
            if cached.files.contains(where: { !$0.included && !$0.isPadding }) {
                restored = try await engine.setFileSelection(
                    id: id, includedFileIDs: cached.files.filter(\.included).map(\.id)
                ).mergingCachedMetadata(from: restored)
            }
            guard pendingAdds[id] == token,
                  let latest = torrents.first(where: { $0.id == id }) else { return }
            if latest.desiredState == .running {
                restored = try await engine.resume(id: id).mergingCachedMetadata(from: restored)
            }
            guard pendingAdds[id] == token,
                  let latest = torrents.first(where: { $0.id == id }) else { return }
            restored = restored.mergingCachedMetadata(from: latest)
            discoveries.removeValue(forKey: id)
            upsert(restored)
            await saveCurrentTorrents()
        } catch {
            let diagnostics = try? await engine.discoverySnapshots()
            guard pendingAdds[id] == token, !Task.isCancelled,
                  let current = torrents.first(where: { $0.id == id }) else { return }
            if let diagnostics { updateDiscoveries(diagnostics) }
            // Preserve tracker results captured above in the final error row.
            let latest = torrents.first(where: { $0.id == id }) ?? current
            upsert(latest.updating(state: "error", downloadBps: 0, uploadBps: 0, error: error.localizedDescription))
            await saveCurrentTorrents()
        }
    }

    private func cancelPendingAdd(id: Torrent.ID) async {
        pendingAdds.removeValue(forKey: id)
        addTasks.removeValue(forKey: id)?.cancel()
        discoveries[id]?.isActive = false
        discoveries[id]?.peersActive = 0
        // UniFFI's generated Swift async wrapper does not propagate Task.cancel().
        // Explicitly abort the Tokio task, rather than just dismissing the UI.
        await engine.cancelPendingAdd(id: id)
    }

    private func updateDiscoveries(_ snapshots: [TorrentDiscovery]) {
        for snapshot in snapshots {
            guard let current = torrents.first(where: { $0.id == snapshot.id }),
                  current.torrentFileBytes == nil, current.desiredState == .running,
                  commandVersions[snapshot.id] == nil else { continue }
            guard discoveries[snapshot.id] != snapshot else { continue }
            discoveries[snapshot.id] = snapshot
            if !snapshot.trackers.isEmpty {
                upsert(current.updating(trackers: snapshot.trackers))
            }
        }
    }

    private func saveCurrentTorrents() async {
        do {
            try await persistence?.save(torrents: torrents)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save the session: \(error.localizedDescription)"
        }
    }

    private func enforceDesiredStates(for liveTorrentIDs: Set<Torrent.ID>) async throws {
        let torrentsToCheck = torrents.filter { liveTorrentIDs.contains($0.id) && pendingAdds[$0.id] == nil && commandVersions[$0.id] == nil }
        for torrent in torrentsToCheck {
            let revision = mutationRevision
            switch (torrent.desiredState, torrent.isPausedInEngine) {
            case (.paused, false):
                let liveTorrent = try await engine.pause(id: torrent.id)
                    .mergingCachedMetadata(from: torrent)
                    .updating(desiredState: .paused)
                guard revision == mutationRevision else { continue }
                upsert(liveTorrent)
                try await persistence?.save(torrent: liveTorrent)

            case (.running, true):
                let liveTorrent = try await engine.resume(id: torrent.id)
                    .mergingCachedMetadata(from: torrent)
                    .updating(desiredState: .running)
                guard revision == mutationRevision else { continue }
                upsert(liveTorrent)
                try await persistence?.save(torrent: liveTorrent)

            case (.paused, true), (.running, false):
                break
            }
        }
    }

    private func pause(_ torrent: Torrent) async {
        await setDesiredState(.paused, for: torrent.id)
    }

    private func resume(_ torrent: Torrent) async {
        await setDesiredState(.running, for: torrent.id)
    }

    private func setDesiredState(_ desiredState: TorrentDesiredState, for id: Torrent.ID) async {
        await launchTask?.value
        guard let current = torrents.first(where: { $0.id == id }), engineError == nil else { return }
        let token = UUID()
        commandVersions[id] = token
        mutationRevision += 1
        defer {
            if commandVersions[id] == token { commandVersions.removeValue(forKey: id) }
            mutationRevision += 1
        }
        let updated = current.updating(
            desiredState: desiredState,
            state: !managedTorrentIDs.contains(id) && desiredState == .paused ? "paused" : current.state,
            downloadBps: 0, uploadBps: 0, clearError: true
        )
        upsert(updated)
        var savedIntent = false
        do {
            // Persist intent before the engine acknowledges it.
            try await persistence?.save(torrent: updated)
            savedIntent = true
            guard commandVersions[id] == token else { return }
            if pendingAdds[id] != nil { await cancelPendingAdd(id: id) }
            guard commandVersions[id] == token else { return }
            if !managedTorrentIDs.contains(id) {
                if desiredState == .running { startAddingToEngine(updated) }
                return
            }
            let snapshot = desiredState == .paused
                ? try await engine.pause(id: id)
                : try await engine.resume(id: id)
            guard commandVersions[id] == token,
                  let latest = torrents.first(where: { $0.id == id }) else { return }
            let result = snapshot.mergingCachedMetadata(from: latest)
            upsert(result)
            try await persistence?.save(torrent: result)
            lastError = nil
        } catch {
            guard commandVersions[id] == token else { return }
            if !savedIntent {
                upsert(current)
                persistenceError = "Could not save transfer state: \(error.localizedDescription)"
            }
            lastError = error.localizedDescription
        }
    }

    private func remove(_ torrent: Torrent, deleteData: Bool) async {
        await launchTask?.value
        mutationRevision += 1
        commandVersions.removeValue(forKey: torrent.id)
        let wasPending = pendingAdds[torrent.id] != nil || !managedTorrentIDs.contains(torrent.id)
        await cancelPendingAdd(id: torrent.id)
        locallyRemovedTorrentIDs.insert(torrent.id)
        torrents.removeAll { $0.id == torrent.id }
        discoveries.removeValue(forKey: torrent.id)
        if selection == torrent.id {
            selection = torrents.first?.id
        }
        do {
            try await persistence?.deleteTorrent(id: torrent.id)
        } catch {
            locallyRemovedTorrentIDs.remove(torrent.id)
            let message = "Could not save the removal: \(error.localizedDescription)"
            upsert(torrent.updating(state: "error", error: message))
            persistenceError = message
            return
        }

        do {
            if !wasPending || managedTorrentIDs.contains(torrent.id) {
                try await engine.remove(id: torrent.id, deleteData: deleteData)
            }
            managedTorrentIDs.remove(torrent.id)
            try await persistence?.deleteTorrent(id: torrent.id)
        } catch {
            if deleteData, isEngineDataCleanupFailureAfterTorrentRemoval(error) {
                await handlePartialEngineDataDeletionFailure(error, for: torrent)
                return
            }

            locallyRemovedTorrentIDs.remove(torrent.id)
            upsert(torrent)
            try? await persistence?.save(torrent: torrent)
            lastError = error.localizedDescription
            return
        }

        guard deleteData else {
            lastError = nil
            return
        }

        do {
            try deleteDownloadedData(for: torrent)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handlePartialEngineDataDeletionFailure(_ engineError: Error, for torrent: Torrent) async {
        let engineMessage = engineError.localizedDescription
        try? await persistence?.deleteTorrent(id: torrent.id)

        do {
            try deleteDownloadedData(for: torrent)
            lastError = "rqbit reported a file cleanup failure after removing the torrent; Sweep removed cached files locally. \(engineMessage)"
        } catch {
            lastError = "rqbit reported a file cleanup failure after removing the torrent: \(engineMessage). Sweep local cleanup also failed: \(error.localizedDescription)"
        }
    }

    private func isEngineDataCleanupFailureAfterTorrentRemoval(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("torrent deleted, but could not delete files")
            || message.contains("deleted, but could not delete files")
            || message.contains("could not delete all torrent payload files")
    }

    private func setFileSelection(file: TorrentFile, included: Bool, in torrent: Torrent) async {
        var includedFileIDs = Set(torrent.files.filter(\.included).map(\.id))
        if included {
            includedFileIDs.insert(file.id)
        } else {
            includedFileIDs.remove(file.id)
        }

        guard !includedFileIDs.isEmpty else {
            lastError = "At least one file must remain selected for download."
            return
        }

        do {
            let liveTorrent = try await engine
                .setFileSelection(id: torrent.id, includedFileIDs: includedFileIDs.sorted())
                .mergingCachedMetadata(from: torrent)
            upsert(liveTorrent)
            try await persistence?.save(torrent: liveTorrent)
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

    private func filterVisibleLiveTorrents(from liveTorrents: [Torrent]) -> [Torrent] {
        liveTorrents.filter { !locallyRemovedTorrentIDs.contains($0.id) }
    }

    private func discardLocallyRemovedTorrents() {
        torrents.removeAll { locallyRemovedTorrentIDs.contains($0.id) }
    }

    private func createDownloadDirectory(at path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func deleteDownloadedData(for torrent: Torrent) throws {
        let baseDirectory = torrent.downloadDirectory ?? downloadDirectory
        guard !baseDirectory.isEmpty else { return }

        let baseURL = URL(filePath: baseDirectory, directoryHint: .isDirectory)
            .standardizedFileURL
        let fileManager = FileManager.default
        var candidateDirectories = Set<URL>()

        for file in torrent.files where !file.isPadding {
            let fileURL = try downloadedFileURL(for: file.path, under: baseURL)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            collectParentDirectories(of: fileURL, under: baseURL, into: &candidateDirectories)
        }

        for directory in candidateDirectories.sorted(by: { $0.path.count > $1.path.count }) {
            try removeDirectoryIfEmpty(directory, fileManager: fileManager)
        }
    }

    private func downloadedFileURL(for relativePath: String, under baseURL: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw TorrentDataDeletionError(path: relativePath)
        }

        let fileURL = baseURL
            .appending(path: relativePath)
            .standardizedFileURL
        guard isPath(fileURL.path, containedIn: baseURL.path) else {
            throw TorrentDataDeletionError(path: relativePath)
        }
        return fileURL
    }

    private func collectParentDirectories(
        of fileURL: URL,
        under baseURL: URL,
        into directories: inout Set<URL>
    ) {
        var directory = fileURL.deletingLastPathComponent().standardizedFileURL
        while directory.path != baseURL.path, isPath(directory.path, containedIn: baseURL.path) {
            directories.insert(directory)
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }

    private func removeDirectoryIfEmpty(_ directory: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard contents.isEmpty else { return }
        try fileManager.removeItem(at: directory)
    }

    private func isPath(_ path: String, containedIn basePath: String) -> Bool {
        path == basePath || path.hasPrefix(basePath + "/")
    }
}

private let transferRateSmoothingAlpha = 0.35
private let activeTransferRateThreshold = 1.0

private struct TorrentDataDeletionError: LocalizedError {
    let path: String

    var errorDescription: String? {
        "Refusing to delete torrent data outside the download directory: \(path)"
    }
}

private func smoothedRate(
    _ current: Double,
    previous: Double?,
    holdTransientZero: Bool = false
) -> Double {
    let normalizedCurrent = current.isFinite ? max(0, current) : 0
    guard normalizedCurrent > activeTransferRateThreshold else {
        guard
            holdTransientZero,
            let previous,
            previous.isFinite,
            previous > activeTransferRateThreshold
        else {
            return normalizedCurrent
        }
        let decayed = previous * (1 - transferRateSmoothingAlpha)
        return decayed > activeTransferRateThreshold ? decayed : 0
    }
    guard let previous, previous.isFinite, previous > activeTransferRateThreshold else {
        return normalizedCurrent
    }
    return previous + (normalizedCurrent - previous) * transferRateSmoothingAlpha
}

private func smoothedOptionalRate(
    _ current: Double?,
    previous: Double?,
    holdTransientZero: Bool = false
) -> Double? {
    guard let current else { return nil }
    return smoothedRate(current, previous: previous, holdTransientZero: holdTransientZero)
}

private extension TorrentSessionStats {
    func smoothed(from previous: TorrentSessionStats) -> TorrentSessionStats {
        let shouldHoldTransientZero = livePeers > 0 || previous.livePeers > 0
        return TorrentSessionStats(
            downloadBps: smoothedRate(
                downloadBps,
                previous: previous.downloadBps,
                holdTransientZero: shouldHoldTransientZero
            ),
            uploadBps: smoothedRate(
                uploadBps,
                previous: previous.uploadBps,
                holdTransientZero: shouldHoldTransientZero
            ),
            downloadedBytes: downloadedBytes,
            uploadedBytes: uploadedBytes,
            livePeers: livePeers,
            connectingPeers: connectingPeers,
            queuedPeers: queuedPeers,
            seenPeers: seenPeers,
            uptimeSeconds: uptimeSeconds,
            network: network
        )
    }
}

private extension Torrent {
    func withSmoothedTransferStats(from cached: Torrent) -> Torrent {
        let shouldHoldTransfer = shouldHoldTransientTransferStats
        return updating(
            downloadBps: smoothedRate(
                downloadBps,
                previous: cached.downloadBps,
                holdTransientZero: shouldHoldTransfer && remainingBytes > 0
            ),
            uploadBps: smoothedRate(
                uploadBps,
                previous: cached.uploadBps,
                holdTransientZero: shouldHoldTransfer && (progress >= 1 || cached.uploadBps > activeTransferRateThreshold)
            ),
            updatedAt: updatedAt
        )
    }

    func withEstimatedPeerRates(from cached: Torrent) -> Torrent {
        let elapsed = updatedAt.timeIntervalSince(cached.updatedAt)
        guard elapsed > 0.05 else { return self }

        var cachedPeers: [TorrentPeer.ID: TorrentPeer] = [:]
        for peer in cached.peers {
            cachedPeers[peer.id] = peer
        }
        let peers = peers.map { peer in
            guard let previous = cachedPeers[peer.id] else { return peer }
            let downloadBps = peer.downloadBps ?? estimatedRate(
                currentBytes: peer.downloadedBytes,
                previousBytes: previous.downloadedBytes,
                elapsed: elapsed
            )
            let uploadBps = peer.uploadBps ?? estimatedRate(
                currentBytes: peer.uploadedBytes,
                previousBytes: previous.uploadedBytes,
                elapsed: elapsed
            )

            return peer.updatingTransferRates(
                downloadBps: smoothedOptionalRate(
                    downloadBps,
                    previous: previous.downloadBps,
                    holdTransientZero: peer.isLiveConnection
                ),
                uploadBps: smoothedOptionalRate(
                    uploadBps,
                    previous: previous.uploadBps,
                    holdTransientZero: peer.isLiveConnection
                )
            )
        }

        return updating(peers: peers, updatedAt: updatedAt)
    }

    private var shouldHoldTransientTransferStats: Bool {
        desiredState == .running && !isPausedInEngine && error == nil
    }

    private func estimatedRate(
        currentBytes: UInt64,
        previousBytes: UInt64,
        elapsed: TimeInterval
    ) -> Double? {
        guard currentBytes >= previousBytes else { return nil }
        return Double(currentBytes - previousBytes) / elapsed
    }
}

public extension TorrentFileSource {
    init(contentsOf url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw TorrentFileSourceError(message: "\(url.lastPathComponent) is not a file.")
        }
        guard url.pathExtension.lowercased() == "torrent" else {
            throw TorrentFileSourceError(message: "Choose a .torrent file.")
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw TorrentFileSourceError(message: "\(url.lastPathComponent) is empty.")
        }

        self.init(fileName: url.lastPathComponent, bytes: Array(data))
    }
}

private struct TorrentFileSourceError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
