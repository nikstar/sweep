import Foundation
import Testing
@testable import SweepActivities

@Suite
struct DownloadActivityContentTests {
    private let date = Date(timeIntervalSince1970: 1_000)
    private func transfer(_ phase: DownloadActivityPhase, id: String = "test", downloaded: UInt64 = 40, total: UInt64 = 100) -> DownloadActivityTransfer {
        .init(id: id, name: "Test download", phase: phase, downloaded: downloaded, total: total,
              downloadBps: 200, uploadBps: 10)
    }

    @Test func pauseAndFailureNeverBecomeCompletion() throws {
        for phase in [DownloadActivityPhase.paused, .failed] {
            let state = try #require(DownloadActivityContent.make(transfers: [transfer(phase)], tracking: ["test"], at: date))
            #expect(state.displayPhase == phase)
            #expect(state.progress == 0.4)
            #expect(state.progressBytes == 40)
            #expect(state.downloadBps == 0)
            #expect(state.uploadBps == 0)
            #expect(state.activeDownloadCount == 0)
            #expect(state.staleDate == nil)
        }
    }

    @Test func oldCompletedOrPausedTorrentsDoNotStartAnActivity() {
        #expect(DownloadActivityContent.make(transfers: [transfer(.completed), transfer(.paused, id: "paused")], tracking: [], at: date) == nil)
        #expect(DownloadActivityContent.make(transfers: [], tracking: ["removed"], at: date) == nil)
    }

    @Test func checkingAFullFileStillRepresentsOngoingWork() throws {
        let state = try #require(DownloadActivityContent.make(transfers: [transfer(.checking, downloaded: 100)], tracking: ["test"], at: date))
        #expect(state.displayPhase == .checking)
        #expect(state.activeDownloadCount == 1)
        #expect(!state.displayPhase.isTerminal)
    }

    @Test func checkingOldCompletedFilesDoesNotReplaceAPausedActivity() throws {
        let old = transfer(.checking, id: "archive", downloaded: 100)
        #expect(DownloadActivityContent.make(transfers: [old], tracking: [], at: date) == nil)
        let state = try #require(DownloadActivityContent.make(
            transfers: [old, transfer(.paused)], tracking: ["test"], at: date))
        #expect(state.displayPhase == .paused)
        #expect(state.torrentIDs == ["test"])
    }

    @Test func finishingOneMemberKeepsTheBatchProgressStable() throws {
        let state = try #require(DownloadActivityContent.make(
            transfers: [transfer(.completed, id: "finished", downloaded: 100), transfer(.downloading)],
            tracking: ["finished", "test"], at: date))
        #expect(state.totalBytes == 200)
        #expect(state.progressBytes == 140)
        #expect(state.activeDownloadCount == 1)
        #expect(state.torrentIDs == ["finished", "test"])
    }

    @Test func finishingUsesVerifiedProgressAndStopsRates() throws {
        let state = try #require(DownloadActivityContent.make(transfers: [transfer(.completed, downloaded: 100)], tracking: ["test"], at: date))
        #expect(state.displayPhase == .completed)
        #expect(state.progress == 1)
        #expect(state.downloadBps == 0)
    }

    @Test func unknownSizesStayIndeterminateAndSeedingDoesNotInflateRates() throws {
        let state = try #require(DownloadActivityContent.make(transfers: [
            transfer(.downloading), transfer(.metadata, id: "unknown", downloaded: 0, total: 0),
            transfer(.completed, id: "old", downloaded: 100)
        ], tracking: [], at: date))
        #expect(state.isIndeterminate)
        #expect(state.activeDownloadCount == 2)
        #expect(state.torrentIDs == ["test", "unknown"])
        #expect(state.totalBytes == 100)
        #expect(state.progressBytes == 40)
        #expect(state.uploadBps == 20)
    }

    @Test func unchangedContentGetsAHeartbeatBeforeItCanBecomeStale() throws {
        let original = try #require(DownloadActivityContent.make(transfers: [transfer(.waiting)], tracking: [], at: date))
        #expect(original.staleDate == date.addingTimeInterval(60))
        var next = original
        next.updatedAt = date.addingTimeInterval(2)
        #expect(!DownloadActivityContent.shouldPublish(next, after: original))
        next.updatedAt = date.addingTimeInterval(10)
        #expect(DownloadActivityContent.shouldPublish(next, after: original))
        let paused = try #require(DownloadActivityContent.make(transfers: [transfer(.paused)], tracking: ["test"], at: date.addingTimeInterval(1)))
        #expect(DownloadActivityContent.shouldPublish(paused, after: original))
    }

    @Test func activitiesFromPreviousBuildsRemainDecodable() throws {
        let current = try #require(DownloadActivityContent.make(transfers: [transfer(.downloading)], tracking: [], at: date))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        json.removeValue(forKey: "phase")
        json.removeValue(forKey: "torrentIDs")
        let restored = try JSONDecoder().decode(SweepDownloadActivityAttributes.ContentState.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.displayPhase == .downloading)
        #expect(restored.progress == 0.4)
        #expect(restored.torrentIDs == nil)
    }
}
