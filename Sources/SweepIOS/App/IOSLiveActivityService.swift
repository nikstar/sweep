import ActivityKit
import Foundation
import Observation
import OSLog
import SweepActivities
import SweepCore
import UIKit

@MainActor @Observable
final class IOSLiveActivityService {
    var isEnabled = UserDefaults.standard.object(forKey: "IOSLiveActivitiesEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "IOSLiveActivitiesEnabled")
            scheduleUpdate()
        }
    }
    private(set) var status = "No active downloads"
    private(set) var lastError: String?
    private(set) var lastUpdateAt: Date?

    @ObservationIgnored private weak var store: TorrentStore?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var activityStateTask: Task<Void, Never>?
    @ObservationIgnored private var needsUpdate = false
    @ObservationIgnored private var lastContent: SweepDownloadActivityAttributes.ContentState?
    @ObservationIgnored private var suppressedIDs: Set<String> = []
    @ObservationIgnored private var retryAfter = Date.distantPast
    @ObservationIgnored private var endingID: String?
    // ActivityKit synchronizes these handles; its SDK interface doesn't express Sendable.
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<SweepDownloadActivityAttributes>?
    private let logger = Logger(subsystem: "me.nikstar.sweep.ios", category: "LiveActivity")
    private static let activityID = "active-downloads"

    func synchronize(store: TorrentStore) async {
        refresh(store: store)
        await updateTask?.value
    }

    func refresh(store: TorrentStore) {
        self.store = store
        scheduleUpdate()
    }

    func showAgain() {
        adoptActivityIfNeeded()
        suppressedIDs.removeAll()
        retryAfter = .distantPast
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        needsUpdate = true
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // All request/update/end operations share one serial worker. Reentrant changes
            // replace its pending input, rather than racing an end against a new request.
            while needsUpdate, !Task.isCancelled {
                needsUpdate = false
                await reconcile()
            }
            updateTask = nil
        }
    }

    private func reconcile() async {
        guard let store else { return }
        adoptActivityIfNeeded()
        guard isEnabled else {
            await endActivity(content: nil, immediately: true)
            status = "Off"
            lastError = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endActivity(content: nil, immediately: true)
            status = "Disabled in iOS Settings"
            lastError = nil
            return
        }
        if store.isRestoringSession, store.torrents.isEmpty {
            status = "Restoring session"
            return
        }
        let transfers = store.torrents.map(DownloadActivityTransfer.init)
        let tracked = Set(activity?.content.state.torrentIDs ?? lastContent?.torrentIDs ?? [])
        guard let content = DownloadActivityContent.make(transfers: transfers, tracking: tracked, at: .now) else {
            await endActivity(content: nil, immediately: true)
            status = "No active downloads"
            suppressedIDs.removeAll()
            return
        }
        let ids = Set(content.torrentIDs ?? [])
        if content.displayPhase.isTerminal {
            await endActivity(content: content, immediately: content.displayPhase == .stopped)
            status = content.detail
            return
        }
        if let activity {
            guard DownloadActivityContent.shouldPublish(content, after: lastContent) else { return }
            nonisolated(unsafe) let handle = activity
            await handle.update(ActivityContent(state: content, staleDate: content.staleDate))
            lastContent = content
            lastUpdateAt = .now
            lastError = nil
            status = content.displayPhase == .paused ? "Active · Paused" : "Active"
            return
        }
        guard content.displayPhase.isActive else { status = "No active downloads"; return }
        guard ids != suppressedIDs else { status = "Dismissed · Show again to restore"; return }
        guard UIApplication.shared.applicationState == .active else {
            status = "Waiting for Sweep to open"
            return
        }
        guard Date.now >= retryAfter else { return }
        do {
            let handle = try Activity.request(
                attributes: SweepDownloadActivityAttributes(activityID: Self.activityID, title: "Sweep"),
                content: ActivityContent(state: content, staleDate: content.staleDate), pushType: nil
            )
            activity = handle
            observeState(of: handle)
            lastContent = content
            lastUpdateAt = .now
            lastError = nil
            status = "Active"
            logger.notice("Live Activity started")
        } catch {
            lastError = error.localizedDescription
            status = "Could not start"
            retryAfter = .now.addingTimeInterval(30)
            logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func adoptActivityIfNeeded() {
        if let activity, ![.active, .stale].contains(activity.activityState) {
            if activity.activityState == .dismissed, endingID != activity.id {
                suppressedIDs = Set(activity.content.state.torrentIDs ?? [])
            }
            self.activity = nil
            lastContent = nil
            activityStateTask?.cancel()
        }
        guard activity == nil else { return }
        if let restored = Activity<SweepDownloadActivityAttributes>.activities.first(where: {
            $0.attributes.activityID == Self.activityID && [.active, .stale].contains($0.activityState)
        }) {
            activity = restored
            // Publish immediately to refresh the deadline and any state from the previous process.
            lastContent = nil
            observeState(of: restored)
            logger.notice("Adopted an existing Live Activity")
        }
    }

    private func observeState(of handle: Activity<SweepDownloadActivityAttributes>) {
        activityStateTask?.cancel()
        nonisolated(unsafe) let handle = handle
        activityStateTask = Task { @MainActor [weak self] in
            for await state in handle.activityStateUpdates {
                guard !Task.isCancelled else { return }
                self?.logger.debug("Live Activity state: \(String(describing: state), privacy: .public)")
                self?.scheduleUpdate()
            }
        }
    }

    private func endActivity(content: SweepDownloadActivityAttributes.ContentState?, immediately: Bool) async {
        guard let activity else { lastContent = nil; return }
        endingID = activity.id
        activityStateTask?.cancel()
        nonisolated(unsafe) let handle = activity
        // Never manufacture 100% on pause, failure, removal, or a preference change.
        await handle.end(
            ActivityContent(state: content ?? handle.content.state, staleDate: nil),
            dismissalPolicy: immediately ? .immediate : .after(.now.addingTimeInterval(120))
        )
        self.activity = nil
        lastContent = nil
        lastUpdateAt = .now
        endingID = nil
        logger.notice("Live Activity ended")
    }
}

private extension DownloadActivityTransfer {
    init(_ torrent: Torrent) {
        let phase: DownloadActivityPhase
        if torrent.error != nil { phase = .failed }
        else if torrent.desiredState == .paused { phase = .paused }
        else if torrent.state == "initializing" || torrent.state == "restoring" { phase = .checking }
        else if torrent.totalBytes == 0 { phase = .metadata }
        else if torrent.progress >= 1 { phase = .completed }
        else if torrent.downloadBps > 1 { phase = .downloading }
        else { phase = .waiting }
        self.init(id: torrent.id, name: torrent.name, phase: phase,
                  downloaded: torrent.progressBytes, total: torrent.totalBytes,
                  downloadBps: torrent.downloadBps.rounded(), uploadBps: torrent.uploadBps.rounded())
    }
}
