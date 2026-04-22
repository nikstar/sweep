import Foundation
import SQLiteData

public struct PersistedAppState: Sendable {
    public let torrents: [Torrent]
    public let selectedTorrentID: Torrent.ID?
    public let downloadDirectory: String?
    public let visibleTorrentColumns: Set<TorrentListColumn>?

    public init(
        torrents: [Torrent],
        selectedTorrentID: Torrent.ID?,
        downloadDirectory: String?,
        visibleTorrentColumns: Set<TorrentListColumn>? = nil
    ) {
        self.torrents = torrents
        self.selectedTorrentID = selectedTorrentID
        self.downloadDirectory = downloadDirectory
        self.visibleTorrentColumns = visibleTorrentColumns
    }
}

public enum AppSettingKey: String, Sendable {
    case selectedTorrentID
    case downloadDirectory
    case visibleTorrentColumns
}

public actor AppPersistence {
    private let database: any DatabaseWriter

    public init(database: any DatabaseWriter) {
        self.database = database
    }

    public nonisolated static func loadState(from database: any DatabaseWriter) throws -> PersistedAppState {
        try database.read { db in
            try readPersistedAppState(db)
        }
    }

    public func loadState() async throws -> PersistedAppState {
        try await database.read { db in
            try readPersistedAppState(db)
        }
    }

    public func save(torrents: [Torrent]) async throws {
        try await database.write { db in
            for torrent in torrents {
                try PersistedTorrent
                    .upsert { PersistedTorrent(torrent: torrent) }
                    .execute(db)
            }
        }
    }

    public func save(torrent: Torrent) async throws {
        try await database.write { db in
            try PersistedTorrent
                .upsert { PersistedTorrent(torrent: torrent) }
                .execute(db)
        }
    }

    public func deleteTorrent(id: Torrent.ID) async throws {
        try await database.write { db in
            try PersistedTorrent
                .where { $0.id.eq(id) }
                .delete()
                .execute(db)
        }
    }

    public func saveSetting(_ key: AppSettingKey, value: String?) async throws {
        try await database.write { db in
            if let value {
                try AppSetting
                    .upsert { AppSetting(id: key.rawValue, value: value) }
                    .execute(db)
            } else {
                try AppSetting
                    .where { $0.id.eq(key.rawValue) }
                    .delete()
                    .execute(db)
            }
        }
    }

    public func saveVisibleTorrentColumns(_ columns: Set<TorrentListColumn>) async throws {
        try await saveSetting(
            .visibleTorrentColumns,
            value: encodeVisibleTorrentColumns(columns)
        )
    }
}

private func readPersistedAppState(_ db: Database) throws -> PersistedAppState {
    let torrents = try PersistedTorrent
        .order(by: \.addedAt)
        .fetchAll(db)
        .map(\.torrent)
    let settings = Dictionary(
        uniqueKeysWithValues: try AppSetting
            .fetchAll(db)
            .map { ($0.id, $0.value) }
    )
    let selectedTorrentID = settings[AppSettingKey.selectedTorrentID.rawValue]
    let validSelection = selectedTorrentID.flatMap { selectedTorrentID in
        torrents.contains { $0.id == selectedTorrentID } ? selectedTorrentID : nil
    }
    return PersistedAppState(
        torrents: torrents,
        selectedTorrentID: validSelection,
        downloadDirectory: settings[AppSettingKey.downloadDirectory.rawValue],
        visibleTorrentColumns: decodeVisibleTorrentColumns(
            settings[AppSettingKey.visibleTorrentColumns.rawValue]
        )
    )
}

@Table("torrents")
private struct PersistedTorrent: Equatable, Identifiable, Sendable {
    let id: String
    var engineID: Int?
    var name: String
    var infoHash: String
    var magnet: String?
    var torrentFileName: String?
    var torrentFileBytes: [UInt8]?
    var downloadDirectory: String?
    var desiredState: String
    var state: String
    var files: String?
    var trackers: String?
    var progressBytes: Int64
    var totalBytes: Int64
    var uploadedBytes: Int64
    var downloadBps: Double
    var uploadBps: Double
    var error: String?
    var addedAt: Double
    var updatedAt: Double

    init(torrent: Torrent) {
        self.id = torrent.id
        self.engineID = torrent.engineID
        self.name = torrent.name
        self.infoHash = torrent.infoHash
        self.magnet = torrent.magnet
        self.torrentFileName = torrent.torrentFileName
        self.torrentFileBytes = torrent.torrentFileBytes
        self.downloadDirectory = torrent.downloadDirectory
        self.desiredState = torrent.desiredState.rawValue
        self.state = torrent.state
        self.files = encodeTorrentFiles(torrent.files)
        self.trackers = encodeTorrentTrackers(torrent.trackers)
        self.progressBytes = Int64(clampingTorrentByteCount: torrent.progressBytes)
        self.totalBytes = Int64(clampingTorrentByteCount: torrent.totalBytes)
        self.uploadedBytes = Int64(clampingTorrentByteCount: torrent.uploadedBytes)
        self.downloadBps = torrent.downloadBps
        self.uploadBps = torrent.uploadBps
        self.error = torrent.error
        self.addedAt = torrent.addedAt.timeIntervalSince1970
        self.updatedAt = torrent.updatedAt.timeIntervalSince1970
    }

    var torrent: Torrent {
        Torrent(
            id: id,
            engineID: engineID,
            name: name,
            infoHash: infoHash,
            magnet: magnet,
            torrentFileName: torrentFileName,
            torrentFileBytes: torrentFileBytes,
            downloadDirectory: downloadDirectory,
            desiredState: TorrentDesiredState(rawValue: desiredState) ?? .running,
            state: state,
            files: decodeTorrentFiles(files),
            trackers: decodeTorrentTrackers(trackers),
            progressBytes: UInt64(nonnegative: progressBytes),
            totalBytes: UInt64(nonnegative: totalBytes),
            uploadedBytes: UInt64(nonnegative: uploadedBytes),
            downloadBps: downloadBps,
            uploadBps: uploadBps,
            error: error,
            addedAt: Date(timeIntervalSince1970: addedAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}

@Table("appSettings")
private struct AppSetting: Equatable, Identifiable, Sendable {
    let id: String
    var value: String
}

private func encodeTorrentFiles(_ files: [TorrentFile]) -> String? {
    guard !files.isEmpty else { return nil }
    guard let data = try? JSONEncoder().encode(files) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeTorrentFiles(_ files: String?) -> [TorrentFile] {
    guard let files, let data = files.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([TorrentFile].self, from: data)) ?? []
}

private func encodeTorrentTrackers(_ trackers: [TorrentTracker]) -> String? {
    guard !trackers.isEmpty else { return nil }
    guard let data = try? JSONEncoder().encode(trackers) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeTorrentTrackers(_ trackers: String?) -> [TorrentTracker] {
    guard let trackers, let data = trackers.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([TorrentTracker].self, from: data)) ?? []
}

private func encodeVisibleTorrentColumns(_ columns: Set<TorrentListColumn>) -> String {
    columns
        .map(\.rawValue)
        .sorted()
        .joined(separator: ",")
}

private func decodeVisibleTorrentColumns(_ value: String?) -> Set<TorrentListColumn>? {
    guard let value else { return nil }
    let columns = value
        .split(separator: ",")
        .compactMap { TorrentListColumn(rawValue: String($0)) }
    return Set(columns)
}

private extension Int64 {
    init(clampingTorrentByteCount value: UInt64) {
        self = value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}

private extension UInt64 {
    init(nonnegative value: Int64) {
        self = value < 0 ? 0 : UInt64(value)
    }
}
