import Foundation

public enum TorrentDesiredState: String, Codable, Hashable, Sendable {
    case running
    case paused
}

public struct Torrent: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let engineID: Int?
    public let name: String
    public let infoHash: String
    public let magnet: String?
    public let downloadDirectory: String?
    public let desiredState: TorrentDesiredState
    public let state: String
    public let progressBytes: UInt64
    public let totalBytes: UInt64
    public let uploadedBytes: UInt64
    public let downloadBps: Double
    public let uploadBps: Double
    public let error: String?
    public let addedAt: Date
    public let updatedAt: Date

    public init(
        id: String? = nil,
        engineID: Int? = nil,
        name: String,
        infoHash: String,
        magnet: String? = nil,
        downloadDirectory: String? = nil,
        desiredState: TorrentDesiredState = .running,
        state: String,
        progressBytes: UInt64,
        totalBytes: UInt64,
        uploadedBytes: UInt64,
        downloadBps: Double,
        uploadBps: Double,
        error: String?,
        addedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let normalizedInfoHash = infoHash.lowercased()
        self.id = id ?? normalizedInfoHash
        self.engineID = engineID
        self.name = name
        self.infoHash = normalizedInfoHash
        self.magnet = magnet
        self.downloadDirectory = downloadDirectory
        self.desiredState = desiredState
        self.state = state
        self.progressBytes = progressBytes
        self.totalBytes = totalBytes
        self.uploadedBytes = uploadedBytes
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.error = error
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case engineID = "engine_id"
        case name
        case infoHash = "info_hash"
        case magnet
        case downloadDirectory = "download_directory"
        case desiredState = "desired_state"
        case state
        case progressBytes = "progress_bytes"
        case totalBytes = "total_bytes"
        case uploadedBytes = "uploaded_bytes"
        case downloadBps = "download_bps"
        case uploadBps = "upload_bps"
        case error
        case addedAt = "added_at"
        case updatedAt = "updated_at"
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(progressBytes) / Double(totalBytes))
    }

    public var statusLabel: String {
        if let error, !error.isEmpty {
            return "Error"
        }
        if desiredState == .paused {
            return isPausedInEngine ? "Paused" : "Pausing"
        }
        if isPausedInEngine {
            return "Resuming"
        }
        if progress >= 1 {
            return "Complete"
        }
        return state.capitalized
    }

    public var isPausedInEngine: Bool {
        state.lowercased() == "paused"
    }

    public func updating(
        engineID: Int? = nil,
        name: String? = nil,
        magnet: String? = nil,
        downloadDirectory: String? = nil,
        desiredState: TorrentDesiredState? = nil,
        state: String? = nil,
        progressBytes: UInt64? = nil,
        totalBytes: UInt64? = nil,
        uploadedBytes: UInt64? = nil,
        downloadBps: Double? = nil,
        uploadBps: Double? = nil,
        error: String? = nil,
        addedAt: Date? = nil,
        updatedAt: Date = Date()
    ) -> Torrent {
        Torrent(
            id: id,
            engineID: engineID ?? self.engineID,
            name: name ?? self.name,
            infoHash: infoHash,
            magnet: magnet ?? self.magnet,
            downloadDirectory: downloadDirectory ?? self.downloadDirectory,
            desiredState: desiredState ?? self.desiredState,
            state: state ?? self.state,
            progressBytes: progressBytes ?? self.progressBytes,
            totalBytes: totalBytes ?? self.totalBytes,
            uploadedBytes: uploadedBytes ?? self.uploadedBytes,
            downloadBps: downloadBps ?? self.downloadBps,
            uploadBps: uploadBps ?? self.uploadBps,
            error: error ?? self.error,
            addedAt: addedAt ?? self.addedAt,
            updatedAt: updatedAt
        )
    }

    public func withMagnet(_ magnet: String?) -> Torrent {
        updating(magnet: magnet)
    }

    public func mergingCachedMetadata(from cached: Torrent) -> Torrent {
        updating(
            magnet: magnet ?? cached.magnet,
            downloadDirectory: downloadDirectory ?? cached.downloadDirectory,
            desiredState: cached.desiredState,
            addedAt: cached.addedAt
        )
    }
}
