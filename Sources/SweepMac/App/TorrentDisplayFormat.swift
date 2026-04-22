import Foundation
import SweepCore

enum TorrentDisplayFormat {
    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = value < 1 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    static func bytesOrUnknown(_ value: UInt64) -> String {
        value == 0 ? "Unknown" : ByteFormatter.bytes(value)
    }

    static func remainingBytes(_ torrent: Torrent) -> String {
        guard torrent.totalBytes > 0 else { return "Unknown" }
        return ByteFormatter.bytes(torrent.remainingBytes)
    }

    static func ratio(_ torrent: Torrent) -> String {
        guard torrent.progressBytes > 0 else { return "0.00" }
        return String(format: "%.2f", Double(torrent.uploadedBytes) / Double(torrent.progressBytes))
    }

    static func sourceType(_ torrent: Torrent) -> String {
        if torrent.magnet != nil {
            return "Magnet"
        }
        if torrent.torrentFileBytes != nil {
            return "Torrent File"
        }
        return "Unknown"
    }

    static func peerConnection(_ peer: TorrentPeer) -> String {
        if let connectionKind = peer.connectionKind, !connectionKind.isEmpty {
            return connectionKind
        }
        if peer.connectionAttempts > 0 {
            return "\(peer.connectionAttempts) attempts"
        }
        return "Queued"
    }

    static func optionalCount<T: BinaryInteger>(_ value: T?) -> String {
        value.map { String($0) } ?? "-"
    }

    static func eta(_ torrent: Torrent) -> String {
        if torrent.progress >= 1 {
            return "Done"
        }
        if torrent.desiredState == .paused {
            return "Paused"
        }
        guard let seconds = torrent.etaSeconds else {
            return "Unknown"
        }
        return duration(seconds)
    }

    static func duration(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

extension TorrentPeer {
    var isLiveConnection: Bool {
        state == "live" || connections > 0
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
