import Foundation

public enum TorrentDesiredState: String, Codable, Hashable, Sendable {
    case running
    case paused
}

public struct TorrentFileSource: Hashable, Codable, Sendable {
    public let fileName: String?
    public let bytes: [UInt8]

    public init(fileName: String?, bytes: [UInt8]) {
        self.fileName = fileName
        self.bytes = bytes
    }
}

public enum TorrentAddSource: Hashable, Sendable {
    case magnet(String)
    case torrentFile(TorrentFileSource)

    public var displayName: String {
        switch self {
        case .magnet(let magnet):
            magnetName(from: magnet) ?? "Magnet Link"

        case .torrentFile(let file):
            file.fileName ?? "Torrent File"
        }
    }

    public var magnet: String? {
        guard case .magnet(let magnet) = self else { return nil }
        return magnet
    }

    public var torrentFile: TorrentFileSource? {
        guard case .torrentFile(let file) = self else { return nil }
        return file
    }

    private func magnetName(from magnet: String) -> String? {
        URLComponents(string: magnet)?
            .queryItems?
            .first { $0.name == "dn" }?
            .value
    }
}

public struct Torrent: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let engineID: Int?
    public let name: String
    public let infoHash: String
    public let magnet: String?
    public let torrentFileName: String?
    public let torrentFileBytes: [UInt8]?
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
        torrentFileName: String? = nil,
        torrentFileBytes: [UInt8]? = nil,
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
        self.torrentFileName = torrentFileName
        self.torrentFileBytes = torrentFileBytes
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
        case torrentFileName = "torrent_file_name"
        case torrentFileBytes = "torrent_file_bytes"
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

    public var addSource: TorrentAddSource? {
        if let magnet {
            return .magnet(magnet)
        }
        if let torrentFileBytes {
            return .torrentFile(
                TorrentFileSource(fileName: torrentFileName, bytes: torrentFileBytes)
            )
        }
        return nil
    }

    public func updating(
        engineID: Int? = nil,
        name: String? = nil,
        magnet: String? = nil,
        torrentFileName: String? = nil,
        torrentFileBytes: [UInt8]? = nil,
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
            torrentFileName: torrentFileName ?? self.torrentFileName,
            torrentFileBytes: torrentFileBytes ?? self.torrentFileBytes,
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

    public func withAddSource(_ source: TorrentAddSource) -> Torrent {
        switch source {
        case .magnet(let magnet):
            Torrent(
                id: id,
                engineID: engineID,
                name: name,
                infoHash: infoHash,
                magnet: magnet,
                downloadDirectory: downloadDirectory,
                desiredState: desiredState,
                state: state,
                progressBytes: progressBytes,
                totalBytes: totalBytes,
                uploadedBytes: uploadedBytes,
                downloadBps: downloadBps,
                uploadBps: uploadBps,
                error: error,
                addedAt: addedAt,
                updatedAt: updatedAt
            )

        case .torrentFile(let file):
            Torrent(
                id: id,
                engineID: engineID,
                name: name,
                infoHash: infoHash,
                torrentFileName: file.fileName,
                torrentFileBytes: file.bytes,
                downloadDirectory: downloadDirectory,
                desiredState: desiredState,
                state: state,
                progressBytes: progressBytes,
                totalBytes: totalBytes,
                uploadedBytes: uploadedBytes,
                downloadBps: downloadBps,
                uploadBps: uploadBps,
                error: error,
                addedAt: addedAt,
                updatedAt: updatedAt
            )
        }
    }

    public func mergingCachedMetadata(from cached: Torrent) -> Torrent {
        updating(
            magnet: magnet ?? cached.magnet,
            torrentFileName: torrentFileName ?? cached.torrentFileName,
            torrentFileBytes: torrentFileBytes ?? cached.torrentFileBytes,
            downloadDirectory: downloadDirectory ?? cached.downloadDirectory,
            desiredState: cached.desiredState,
            addedAt: cached.addedAt
        )
    }
}
