import Foundation

public struct Torrent: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let infoHash: String
    public let state: String
    public let progressBytes: UInt64
    public let totalBytes: UInt64
    public let uploadedBytes: UInt64
    public let downloadBps: Double
    public let uploadBps: Double
    public let error: String?

    public init(
        id: Int,
        name: String,
        infoHash: String,
        state: String,
        progressBytes: UInt64,
        totalBytes: UInt64,
        uploadedBytes: UInt64,
        downloadBps: Double,
        uploadBps: Double,
        error: String?
    ) {
        self.id = id
        self.name = name
        self.infoHash = infoHash
        self.state = state
        self.progressBytes = progressBytes
        self.totalBytes = totalBytes
        self.uploadedBytes = uploadedBytes
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case infoHash = "info_hash"
        case state
        case progressBytes = "progress_bytes"
        case totalBytes = "total_bytes"
        case uploadedBytes = "uploaded_bytes"
        case downloadBps = "download_bps"
        case uploadBps = "upload_bps"
        case error
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(progressBytes) / Double(totalBytes))
    }

    public var statusLabel: String {
        if let error, !error.isEmpty {
            return "Error"
        }
        if progress >= 1 {
            return "Complete"
        }
        return state.capitalized
    }
}
