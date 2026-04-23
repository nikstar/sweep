import Foundation

public enum TorrentDisplayFormat {
    public static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = value < 1 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    public static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    public static func bytesOrUnknown(_ value: UInt64) -> String {
        value == 0 ? "Unknown" : ByteFormatter.bytes(value)
    }

    public static func remainingBytes(_ torrent: Torrent) -> String {
        guard torrent.totalBytes > 0 else { return "Unknown" }
        return ByteFormatter.bytes(torrent.remainingBytes)
    }

    public static func ratio(_ torrent: Torrent) -> String {
        guard torrent.progressBytes > 0 else { return "0.00" }
        return String(format: "%.2f", Double(torrent.uploadedBytes) / Double(torrent.progressBytes))
    }

    public static func sourceType(_ torrent: Torrent) -> String {
        if torrent.magnet != nil {
            return "Magnet"
        }
        if torrent.torrentFileBytes != nil {
            return "Torrent File"
        }
        return "Unknown"
    }

    public static func peerConnection(_ peer: TorrentPeer) -> String {
        if let connectionKind = peer.connectionKind, !connectionKind.isEmpty {
            return connectionKind
        }
        if peer.connectionAttempts > 0 {
            return "\(peer.connectionAttempts) attempts"
        }
        return "Queued"
    }

    public static func optionalCount<T: BinaryInteger>(_ value: T?) -> String {
        value.map { String($0) } ?? "-"
    }

    public static func eta(_ torrent: Torrent) -> String {
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

    public static func duration(_ seconds: UInt64) -> String {
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

    public static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
