import ActivityKit
import Foundation
import OSLog
import SweepActivities
import SweepCore

@MainActor
final class IOSLiveActivityService {
    private let settings = IOSLiveActivitySettings()
    private let logger = Logger(subsystem: "me.nikstar.sweep.ios", category: "LiveActivity")
    private var monitorTask: Task<Void, Never>?
    // ActivityKit owns the synchronization for update/end; Swift 6 cannot infer that from the handle.
    nonisolated(unsafe)
    private var activity: Activity<SweepDownloadActivityAttributes>?
    private var lastSnapshot: IOSLiveActivitySnapshot?
    private var lastProblemMessage: String?

    func startMonitoring(store: TorrentStore) {
        guard monitorTask == nil else { return }

        monitorTask = Task { @MainActor in
            while !Task.isCancelled {
                await updateActivity(from: store, reportingTo: store)

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refresh(store: TorrentStore) {
        Task { @MainActor in
            await updateActivity(from: store, reportingTo: store)
        }
    }

    private func updateActivity(from store: TorrentStore, reportingTo reportingStore: TorrentStore?) async {
        guard settings.isEnabled else {
            await endActivity(dismissalPolicy: .immediate)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            reportProblem("Live Activities are disabled for Sweep in Settings.", to: reportingStore)
            await endActivity(dismissalPolicy: .immediate)
            return
        }

        guard let snapshot = IOSLiveActivitySnapshot(torrents: store.torrents, stats: store.sessionStats) else {
            clearProblemIfNeeded(from: reportingStore)
            await endActivity(dismissalPolicy: .after(.now.addingTimeInterval(60)))
            return
        }

        if snapshot == lastSnapshot, currentActivity() != nil {
            return
        }

        let content = ActivityContent(
            state: snapshot.contentState(updatedAt: .now),
            staleDate: .now.addingTimeInterval(15)
        )

        if let currentActivity = currentActivity() {
            nonisolated(unsafe) let activity = currentActivity
            await activity.update(content)
        } else {
            do {
                activity = try Activity.request(
                    attributes: SweepDownloadActivityAttributes(
                        activityID: Self.activityID,
                        title: "Sweep"
                    ),
                    content: content,
                    pushType: nil
                )
            } catch {
                let message = "Live Activity failed to start: \(error.localizedDescription)"
                reportProblem(message, to: reportingStore)
                logger.error("Activity.request failed: \(String(describing: error), privacy: .public)")
                return
            }
        }

        clearProblemIfNeeded(from: reportingStore)
        lastSnapshot = snapshot
    }

    private func endActivity(dismissalPolicy: ActivityUIDismissalPolicy) async {
        guard let currentActivity = currentActivity() else {
            lastSnapshot = nil
            return
        }

        nonisolated(unsafe) let activity = currentActivity
        let finalSnapshot = lastSnapshot?.completed()
        let finalState = finalSnapshot?.contentState(updatedAt: .now)
        await activity.end(
            finalState.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: dismissalPolicy
        )

        self.activity = nil
        lastSnapshot = nil
    }

    private func currentActivity() -> Activity<SweepDownloadActivityAttributes>? {
        if let activity {
            return activity
        }

        let restoredActivity = Activity<SweepDownloadActivityAttributes>.activities.first {
            $0.attributes.activityID == Self.activityID
        }
        activity = restoredActivity
        return restoredActivity
    }

    private func reportProblem(_ message: String, to store: TorrentStore?) {
        if lastProblemMessage != message {
            logger.warning("\(message, privacy: .public)")
        }
        lastProblemMessage = message
        store?.lastError = message
    }

    private func clearProblemIfNeeded(from store: TorrentStore?) {
        guard let lastProblemMessage else { return }
        if store?.lastError == lastProblemMessage {
            store?.lastError = nil
        }
        self.lastProblemMessage = nil
    }

    private static let activityID = "active-downloads"
}

private final class IOSLiveActivitySettings {
    private enum Key {
        static let isEnabled = "IOSLiveActivitiesEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.isEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.isEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.isEnabled)
        }
    }
}

private struct IOSLiveActivitySnapshot: Equatable {
    var headline: String
    var detail: String
    var activeDownloadCount: Int
    var progress: Double
    var progressBytes: UInt64
    var totalBytes: UInt64
    var downloadBps: Double
    var uploadBps: Double
    var isIndeterminate: Bool

    init?(torrents: [Torrent], stats: TorrentSessionStats) {
        let activeDownloads = torrents.filter { torrent in
            torrent.desiredState == .running
                && torrent.error == nil
                && (torrent.totalBytes == 0 || torrent.progress < 1)
        }

        guard !activeDownloads.isEmpty else { return nil }

        let primaryTorrent = activeDownloads.max { lhs, rhs in
            if lhs.downloadBps == rhs.downloadBps {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.downloadBps < rhs.downloadBps
        } ?? activeDownloads[0]

        let totalBytes = activeDownloads.reduce(UInt64(0)) { $0 + $1.totalBytes }
        let progressBytes = activeDownloads.reduce(UInt64(0)) { $0 + $1.progressBytes }
        let hasUnknownSize = activeDownloads.contains { $0.totalBytes == 0 }
        let progress = Self.progress(progressBytes: progressBytes, totalBytes: totalBytes)

        if activeDownloads.count == 1 {
            headline = primaryTorrent.name
            detail = primaryTorrent.totalBytes == 0 ? "Waiting for metadata" : "\(Self.percent(progress)) downloaded"
        } else {
            headline = "\(activeDownloads.count) active downloads"
            detail = primaryTorrent.name
        }

        activeDownloadCount = activeDownloads.count
        self.progress = Self.round(progress, scale: 1_000)
        self.progressBytes = progressBytes
        self.totalBytes = totalBytes
        downloadBps = Self.round(stats.downloadBps, scale: 1)
        uploadBps = Self.round(stats.uploadBps, scale: 1)
        isIndeterminate = hasUnknownSize || totalBytes == 0
    }

    func contentState(updatedAt: Date) -> SweepDownloadActivityAttributes.ContentState {
        SweepDownloadActivityAttributes.ContentState(
            headline: headline,
            detail: detail,
            activeDownloadCount: activeDownloadCount,
            progress: progress,
            progressBytes: progressBytes,
            totalBytes: totalBytes,
            downloadBps: downloadBps,
            uploadBps: uploadBps,
            isIndeterminate: isIndeterminate,
            updatedAt: updatedAt
        )
    }

    func completed() -> IOSLiveActivitySnapshot {
        var snapshot = self
        snapshot.detail = activeDownloadCount == 1 ? "Download complete" : "Downloads complete"
        snapshot.progress = 1
        snapshot.progressBytes = max(progressBytes, totalBytes)
        snapshot.downloadBps = 0
        snapshot.uploadBps = 0
        snapshot.isIndeterminate = false
        return snapshot
    }

    private static func progress(progressBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(min(progressBytes, totalBytes)) / Double(totalBytes))
    }

    private static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    private static func round(_ value: Double, scale: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * scale).rounded() / scale
    }
}
