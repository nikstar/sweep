import Foundation

public enum DownloadActivityPhase: String, Codable, Hashable, Sendable {
    case metadata, checking, downloading, waiting, paused, failed, completed, stopped

    public var isActive: Bool { [.metadata, .checking, .downloading, .waiting].contains(self) }
    public var isTerminal: Bool { [.failed, .completed, .stopped].contains(self) }
    public var title: String {
        switch self {
        case .metadata: "Finding metadata"
        case .checking: "Checking files"
        case .downloading: "Downloading"
        case .waiting: "Waiting for peers"
        case .paused: "Paused"
        case .failed: "Needs attention"
        case .completed: "Download complete"
        case .stopped: "Transfers removed"
        }
    }
    public var symbol: String {
        switch self {
        case .metadata, .waiting: "network"
        case .checking: "arrow.trianglehead.2.clockwise"
        case .downloading: "arrow.down"
        case .paused: "pause.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .completed: "checkmark"
        case .stopped: "stop.fill"
        }
    }
}

/// A small projection keeps the widget extension independent of the database and torrent engine.
public struct DownloadActivityTransfer: Sendable {
    public let id: String
    public let name: String
    public let phase: DownloadActivityPhase
    public let downloaded: UInt64
    public let total: UInt64
    public let downloadBps: Double
    public let uploadBps: Double

    public init(id: String, name: String, phase: DownloadActivityPhase, downloaded: UInt64, total: UInt64,
                downloadBps: Double = 0, uploadBps: Double = 0) {
        self.id = id; self.name = name; self.phase = phase
        self.downloaded = downloaded; self.total = total
        self.downloadBps = downloadBps; self.uploadBps = uploadBps
    }
}

public enum DownloadActivityContent {
    public static func make(
        transfers: [DownloadActivityTransfer], tracking ids: Set<String>, at date: Date
    ) -> SweepDownloadActivityAttributes.ContentState? {
        let active = transfers.filter {
            guard $0.phase.isActive else { return false }
            // Launch verifies old completed files too. That must not replace a restored,
            // paused activity or create a new download activity for the archive.
            return $0.phase != .checking || $0.total == 0 || $0.downloaded < $0.total || ids.contains($0.id)
        }
        let activeIDs = Set(active.map(\.id))
        // Retain this batch as individual transfers finish or pause, so its total and
        // progress do not jump when one member leaves the active set.
        let relevant = transfers.filter { activeIDs.contains($0.id) || ids.contains($0.id) }
        guard !relevant.isEmpty else { return nil }
        let phase: DownloadActivityPhase
        if !active.isEmpty {
            phase = [.downloading, .checking, .metadata, .waiting].first { phase in
                active.contains { $0.phase == phase }
            } ?? .waiting
        } else if relevant.contains(where: { $0.phase == .failed }) {
            phase = .failed
        } else if relevant.contains(where: { $0.phase == .paused }) {
            phase = .paused
        } else if relevant.allSatisfy({ $0.phase == .completed }) {
            phase = .completed
        } else {
            phase = .stopped
        }
        let total = relevant.reduce(UInt64(0)) { $0.addingClamped($1.total) }
        let downloaded = relevant.reduce(UInt64(0)) { $0.addingClamped(min($1.downloaded, $1.total)) }
        let unknown = relevant.contains { $0.total == 0 }
        return .init(
            headline: relevant.count == 1 ? relevant[0].name : "\(relevant.count) downloads",
            detail: phase == .completed && relevant.count > 1 ? "Downloads complete" : phase.title,
            activeDownloadCount: active.count,
            progress: total > 0 ? Double(downloaded) / Double(total) : 0,
            progressBytes: downloaded, totalBytes: total,
            downloadBps: phase.isActive ? active.reduce(0) { $0 + $1.downloadBps } : 0,
            uploadBps: phase.isActive ? active.reduce(0) { $0 + $1.uploadBps } : 0,
            isIndeterminate: unknown, updatedAt: date,
            phase: phase, torrentIDs: relevant.map(\.id).sorted()
        )
    }

    public static func shouldPublish(
        _ content: SweepDownloadActivityAttributes.ContentState,
        after previous: SweepDownloadActivityAttributes.ContentState?
    ) -> Bool {
        guard var previous else { return true }
        // Refresh staleDate even while no bytes move. Never leave an unchanged transfer stale.
        if content.updatedAt.timeIntervalSince(previous.updatedAt) >= 10 { return true }
        previous.updatedAt = content.updatedAt
        return previous != content
    }
}

private extension UInt64 {
    func addingClamped(_ other: UInt64) -> UInt64 {
        let result = addingReportingOverflow(other)
        return result.overflow ? .max : result.partialValue
    }
}
