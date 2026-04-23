import Foundation

public enum TorrentDesiredState: String, Codable, Hashable, Sendable {
    case running
    case paused
}

public enum TorrentPieceState: String, Codable, CaseIterable, Hashable, Sendable {
    case downloaded
    case downloading
    case needed
    case skipped
    case unknown
}

public struct TorrentPieceRun: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let state: TorrentPieceState
    public let pieceCount: UInt64
    public let byteCount: UInt64

    public init(
        id: Int,
        state: TorrentPieceState,
        pieceCount: UInt64,
        byteCount: UInt64
    ) {
        self.id = id
        self.state = state
        self.pieceCount = pieceCount
        self.byteCount = byteCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case pieceCount = "piece_count"
        case byteCount = "byte_count"
    }
}

public struct TorrentSessionStats: Hashable, Codable, Sendable {
    public static let empty = TorrentSessionStats()

    public let downloadBps: Double
    public let uploadBps: Double
    public let downloadedBytes: UInt64
    public let uploadedBytes: UInt64
    public let livePeers: UInt32
    public let connectingPeers: UInt32
    public let queuedPeers: UInt32
    public let seenPeers: UInt32
    public let uptimeSeconds: UInt64

    public init(
        downloadBps: Double = 0,
        uploadBps: Double = 0,
        downloadedBytes: UInt64 = 0,
        uploadedBytes: UInt64 = 0,
        livePeers: UInt32 = 0,
        connectingPeers: UInt32 = 0,
        queuedPeers: UInt32 = 0,
        seenPeers: UInt32 = 0,
        uptimeSeconds: UInt64 = 0
    ) {
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.livePeers = livePeers
        self.connectingPeers = connectingPeers
        self.queuedPeers = queuedPeers
        self.seenPeers = seenPeers
        self.uptimeSeconds = uptimeSeconds
    }
}

public enum TorrentListColumn: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case size
    case eta
    case progress
    case remaining
    case speed
    case peers

    public var id: String { rawValue }

    public static let defaultVisible: Set<TorrentListColumn> = [
        .size,
        .progress,
        .remaining,
        .speed,
        .peers
    ]
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

public struct TorrentFile: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let path: String
    public let length: UInt64
    public let progressBytes: UInt64
    public let progressRuns: [TorrentPieceRun]
    public let included: Bool
    public let isPadding: Bool
    public let priority: String

    public init(
        id: Int,
        path: String,
        length: UInt64,
        progressBytes: UInt64,
        progressRuns: [TorrentPieceRun] = [],
        included: Bool = true,
        isPadding: Bool = false,
        priority: String = "normal"
    ) {
        self.id = id
        self.path = path
        self.length = length
        self.progressBytes = progressBytes
        self.progressRuns = progressRuns
        self.included = included
        self.isPadding = isPadding
        self.priority = priority
    }

    public var name: String {
        (path as NSString).lastPathComponent
    }

    public var progress: Double {
        guard length > 0 else { return 0 }
        return min(1, Double(min(progressBytes, length)) / Double(length))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case length
        case progressBytes
        case progressRuns
        case included
        case isPadding
        case priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            path: try container.decode(String.self, forKey: .path),
            length: try container.decode(UInt64.self, forKey: .length),
            progressBytes: try container.decode(UInt64.self, forKey: .progressBytes),
            progressRuns: try container.decodeIfPresent([TorrentPieceRun].self, forKey: .progressRuns) ?? [],
            included: try container.decodeIfPresent(Bool.self, forKey: .included) ?? true,
            isPadding: try container.decodeIfPresent(Bool.self, forKey: .isPadding) ?? false,
            priority: try container.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
        )
    }
}

public struct TorrentTracker: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let url: String
    public let kind: String
    public let scrapeURL: String?
    public let status: String
    public let lastError: String?
    public let lastAnnounceAt: Date?
    public let nextAnnounceAt: Date?
    public let seeders: UInt32?
    public let leechers: UInt32?
    public let downloads: UInt32?
    public let lastPeerCount: UInt64?

    public init(
        id: Int,
        url: String,
        kind: String = "Unknown",
        scrapeURL: String? = nil,
        status: String = "Configured",
        lastError: String? = nil,
        lastAnnounceAt: Date? = nil,
        nextAnnounceAt: Date? = nil,
        seeders: UInt32? = nil,
        leechers: UInt32? = nil,
        downloads: UInt32? = nil,
        lastPeerCount: UInt64? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.scrapeURL = scrapeURL
        self.status = status
        self.lastError = lastError
        self.lastAnnounceAt = lastAnnounceAt
        self.nextAnnounceAt = nextAnnounceAt
        self.seeders = seeders
        self.leechers = leechers
        self.downloads = downloads
        self.lastPeerCount = lastPeerCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case kind
        case scrapeURL
        case status
        case lastError
        case lastAnnounceAt
        case nextAnnounceAt
        case seeders
        case leechers
        case downloads
        case lastPeerCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            url: try container.decode(String.self, forKey: .url),
            kind: try container.decodeIfPresent(String.self, forKey: .kind) ?? "Unknown",
            scrapeURL: try container.decodeIfPresent(String.self, forKey: .scrapeURL),
            status: try container.decodeIfPresent(String.self, forKey: .status) ?? "Configured",
            lastError: try container.decodeIfPresent(String.self, forKey: .lastError),
            lastAnnounceAt: try container.decodeIfPresent(Date.self, forKey: .lastAnnounceAt),
            nextAnnounceAt: try container.decodeIfPresent(Date.self, forKey: .nextAnnounceAt),
            seeders: try container.decodeIfPresent(UInt32.self, forKey: .seeders),
            leechers: try container.decodeIfPresent(UInt32.self, forKey: .leechers),
            downloads: try container.decodeIfPresent(UInt32.self, forKey: .downloads),
            lastPeerCount: try container.decodeIfPresent(UInt64.self, forKey: .lastPeerCount)
        )
    }
}

public struct TorrentPeer: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let address: String
    public let state: String
    public let connectionKind: String?
    public let peerID: String?
    public let client: String?
    public let featureFlags: [String]
    public let countryCode: String?
    public let availability: Double?
    public let availablePieces: UInt32?
    public let downloadedBytes: UInt64
    public let uploadedBytes: UInt64
    public let downloadBps: Double?
    public let uploadBps: Double?
    public let connectionAttempts: UInt32
    public let connections: UInt32
    public let errors: UInt32

    public init(
        id: String? = nil,
        address: String,
        state: String,
        connectionKind: String?,
        peerID: String? = nil,
        client: String? = nil,
        featureFlags: [String] = [],
        countryCode: String? = nil,
        availability: Double? = nil,
        availablePieces: UInt32? = nil,
        downloadedBytes: UInt64,
        uploadedBytes: UInt64,
        downloadBps: Double? = nil,
        uploadBps: Double? = nil,
        connectionAttempts: UInt32,
        connections: UInt32,
        errors: UInt32
    ) {
        self.id = id ?? address
        self.address = address
        self.state = state
        self.connectionKind = connectionKind
        self.peerID = peerID
        self.client = client
        self.featureFlags = featureFlags
        self.countryCode = countryCode
        self.availability = availability
        self.availablePieces = availablePieces
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.connectionAttempts = connectionAttempts
        self.connections = connections
        self.errors = errors
    }

    enum CodingKeys: String, CodingKey {
        case id
        case address
        case state
        case connectionKind
        case peerID
        case client
        case featureFlags
        case countryCode
        case availability
        case availablePieces
        case downloadedBytes
        case uploadedBytes
        case downloadBps
        case uploadBps
        case connectionAttempts
        case connections
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let address = try container.decode(String.self, forKey: .address)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            address: address,
            state: try container.decode(String.self, forKey: .state),
            connectionKind: try container.decodeIfPresent(String.self, forKey: .connectionKind),
            peerID: try container.decodeIfPresent(String.self, forKey: .peerID),
            client: try container.decodeIfPresent(String.self, forKey: .client),
            featureFlags: try container.decodeIfPresent([String].self, forKey: .featureFlags) ?? [],
            countryCode: try container.decodeIfPresent(String.self, forKey: .countryCode),
            availability: try container.decodeIfPresent(Double.self, forKey: .availability),
            availablePieces: try container.decodeIfPresent(UInt32.self, forKey: .availablePieces),
            downloadedBytes: try container.decode(UInt64.self, forKey: .downloadedBytes),
            uploadedBytes: try container.decode(UInt64.self, forKey: .uploadedBytes),
            downloadBps: try container.decodeIfPresent(Double.self, forKey: .downloadBps),
            uploadBps: try container.decodeIfPresent(Double.self, forKey: .uploadBps),
            connectionAttempts: try container.decode(UInt32.self, forKey: .connectionAttempts),
            connections: try container.decode(UInt32.self, forKey: .connections),
            errors: try container.decode(UInt32.self, forKey: .errors)
        )
    }

    public func updatingTransferRates(downloadBps: Double?, uploadBps: Double?) -> TorrentPeer {
        TorrentPeer(
            id: id,
            address: address,
            state: state,
            connectionKind: connectionKind,
            peerID: peerID,
            client: client,
            featureFlags: featureFlags,
            countryCode: countryCode,
            availability: availability,
            availablePieces: availablePieces,
            downloadedBytes: downloadedBytes,
            uploadedBytes: uploadedBytes,
            downloadBps: downloadBps,
            uploadBps: uploadBps,
            connectionAttempts: connectionAttempts,
            connections: connections,
            errors: errors
        )
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
    public let files: [TorrentFile]
    public let trackers: [TorrentTracker]
    public let peers: [TorrentPeer]
    public let pieceRuns: [TorrentPieceRun]
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
        files: [TorrentFile] = [],
        trackers: [TorrentTracker] = [],
        peers: [TorrentPeer] = [],
        pieceRuns: [TorrentPieceRun] = [],
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
        self.files = files
        self.trackers = trackers
        self.peers = peers
        self.pieceRuns = pieceRuns
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
        case files
        case trackers
        case peers
        case pieceRuns = "piece_runs"
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

    public var remainingBytes: UInt64 {
        totalBytes > progressBytes ? totalBytes - progressBytes : 0
    }

    public var etaSeconds: UInt64? {
        guard remainingBytes > 0, downloadBps > 1 else { return nil }
        return UInt64((Double(remainingBytes) / downloadBps).rounded(.up))
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
        files: [TorrentFile]? = nil,
        trackers: [TorrentTracker]? = nil,
        peers: [TorrentPeer]? = nil,
        pieceRuns: [TorrentPieceRun]? = nil,
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
            files: files ?? self.files,
            trackers: trackers ?? self.trackers,
            peers: peers ?? self.peers,
            pieceRuns: pieceRuns ?? self.pieceRuns,
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
                files: files,
                trackers: trackers,
                peers: peers,
                pieceRuns: pieceRuns,
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
                files: files,
                trackers: trackers,
                peers: peers,
                pieceRuns: pieceRuns,
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
            trackers: trackers.isEmpty ? cached.trackers : trackers,
            pieceRuns: pieceRuns.isEmpty ? cached.pieceRuns : pieceRuns,
            addedAt: cached.addedAt
        )
    }
}
