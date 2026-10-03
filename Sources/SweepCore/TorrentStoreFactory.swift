import Foundation
import SQLiteData

/// Keeps engine failures separate from storage failures so saved transfers remain visible.
@MainActor
public enum TorrentStoreFactory {
    public static func make(
        defaultDownloadDirectory: String,
        openDatabase: () throws -> any DatabaseWriter = SweepDatabase.openDefault,
        prepareState: (PersistedAppState) -> PersistedAppState = { $0 },
        prepareDirectory: (String) throws -> Void = { path in
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        },
        makeEngine: (String) throws -> any TorrentEngine
    ) -> TorrentStore {
        var persistence: AppPersistence?
        var state: PersistedAppState?
        var storageError: String?
        do {
            let database = try openDatabase()
            state = prepareState(try AppPersistence.loadState(from: database))
            persistence = AppPersistence(database: database)
        } catch {
            storageError = "Session storage is unavailable; changes cannot be restored after quitting. \(error.localizedDescription)"
        }

        let directory = state?.downloadDirectory ?? defaultDownloadDirectory
        let engine: any TorrentEngine
        do {
            try prepareDirectory(directory)
            engine = try makeEngine(directory)
        } catch {
            engine = UnavailableTorrentEngine(reason: error.localizedDescription)
        }
        return TorrentStore(
            engine: engine, persistence: persistence, downloadDirectory: directory,
            initialState: state, initialError: storageError
        )
    }
}
