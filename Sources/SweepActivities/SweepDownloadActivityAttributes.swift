#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

public struct SweepDownloadActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let headline: String
        public let detail: String
        public let activeDownloadCount: Int
        public let progress: Double
        public let progressBytes: UInt64
        public let totalBytes: UInt64
        public let downloadBps: Double
        public let uploadBps: Double
        public let isIndeterminate: Bool
        public var updatedAt: Date
        // Optional for activities restored from an older app build.
        public let phase: DownloadActivityPhase?
        public let torrentIDs: [String]?

        public var displayPhase: DownloadActivityPhase {
            phase ?? (isIndeterminate ? .metadata : (progress >= 1 ? .completed : .downloading))
        }

        public var staleDate: Date? {
            // A paused transfer is a stable state, even after the app is suspended.
            displayPhase.isActive ? updatedAt.addingTimeInterval(60) : nil
        }

        public init(
            headline: String,
            detail: String,
            activeDownloadCount: Int,
            progress: Double,
            progressBytes: UInt64,
            totalBytes: UInt64,
            downloadBps: Double,
            uploadBps: Double,
            isIndeterminate: Bool,
            updatedAt: Date,
            phase: DownloadActivityPhase? = nil,
            torrentIDs: [String]? = nil
        ) {
            self.headline = headline
            self.detail = detail
            self.activeDownloadCount = max(activeDownloadCount, 0)
            self.progress = Self.clampedProgress(progress)
            self.progressBytes = progressBytes
            self.totalBytes = totalBytes
            self.downloadBps = Self.nonnegativeFinite(downloadBps)
            self.uploadBps = Self.nonnegativeFinite(uploadBps)
            self.isIndeterminate = isIndeterminate
            self.updatedAt = updatedAt
            self.phase = phase
            self.torrentIDs = torrentIDs
        }

        public var percentComplete: Int {
            Int((progress * 100).rounded())
        }

        private static func clampedProgress(_ progress: Double) -> Double {
            guard progress.isFinite else { return 0 }
            return min(max(progress, 0), 1)
        }

        private static func nonnegativeFinite(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return max(value, 0)
        }
    }

    public let activityID: String
    public let title: String

    public init(activityID: String, title: String) {
        self.activityID = activityID
        self.title = title
    }
}

#if os(iOS) && canImport(ActivityKit)
extension SweepDownloadActivityAttributes: ActivityAttributes {}
#endif
