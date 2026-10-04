import Foundation

/// File metadata only: never mistakes preallocated bytes or artwork for a movie.
public struct TorrentMedia: Sendable {
    public let videos: [TorrentFile]
    public let primaryVideo: TorrentFile?
    public let isSeries: Bool

    public init(files: [TorrentFile]) {
        videos = files.filter { $0.isVideo && !$0.isSupplementaryVideo }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        isSeries = !videos.isEmpty && videos.allSatisfy(\.isEpisode)
        let largest = videos.sorted { $0.length > $1.length }
        if largest.count == 1 {
            primaryVideo = largest.first
        } else if !isSeries, let first = largest.first,
                  Double(first.length) > Double(largest[1].length) * 2 {
            primaryVideo = first
        } else {
            // A season or collection has several equally important files.
            primaryVideo = nil
        }
    }
}

public extension TorrentFile {
    var isVideo: Bool {
        !isPadding && Self.videoExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    var isEpisode: Bool {
        name.range(of: #"(?i)(?:\b|[._ -])(?:s\d{1,2}e\d{1,3}|\d{1,2}x\d{2,3})(?:\b|[._ -])"#,
                   options: .regularExpression) != nil
    }

    var isSupplementaryVideo: Bool {
        let parts = path.lowercased().split(whereSeparator: { $0 == "/" || $0 == "\\" })
        let folders = parts.dropLast()
        if folders.contains(where: { ["sample", "samples", "extras", "featurettes", "trailers"].contains(String($0)) }) {
            return true
        }
        // Match a release suffix or prefix, not titles such as "The Sample Movie".
        let stem = (name as NSString).deletingPathExtension.lowercased()
        return ["sample", "trailer", "featurette"].contains { marker in
            stem == marker || stem.hasPrefix(marker + ".") || stem.hasPrefix(marker + "-")
                || stem.hasSuffix("." + marker) || stem.hasSuffix("-" + marker)
        }
    }

    private static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "mpg", "mpeg", "ts", "m2ts", "mts", "wmv", "flv", "ogv"
    ]
}
