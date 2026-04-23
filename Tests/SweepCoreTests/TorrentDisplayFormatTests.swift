import Foundation
@testable import SweepCore
import Testing

@Suite
struct TorrentDisplayFormatTests {
    @Test
    func formatsCommonTorrentValues() {
        let torrent = Torrent(
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            desiredState: .running,
            state: "live",
            progressBytes: 500,
            totalBytes: 1_000,
            uploadedBytes: 250,
            downloadBps: 100,
            uploadBps: 0,
            error: nil
        )

        let percent = TorrentDisplayFormat.percent(torrent.progress)
        #expect(percent.contains("50"))
        #expect(percent.contains("%"))
        #expect(TorrentDisplayFormat.ratio(torrent) == "0.50")
        #expect(TorrentDisplayFormat.eta(torrent) == "5s")
        #expect(TorrentDisplayFormat.sourceType(torrent) == "Magnet")
    }

    @Test
    func describesPeerConnection() {
        let livePeer = TorrentPeer(
            address: "127.0.0.1:6881",
            state: "live",
            connectionKind: "utp",
            downloadedBytes: 0,
            uploadedBytes: 0,
            connectionAttempts: 1,
            connections: 1,
            errors: 0
        )
        let queuedPeer = TorrentPeer(
            address: "127.0.0.2:6881",
            state: "queued",
            connectionKind: nil,
            downloadedBytes: 0,
            uploadedBytes: 0,
            connectionAttempts: 0,
            connections: 0,
            errors: 0
        )

        #expect(livePeer.isLiveConnection)
        #expect(TorrentDisplayFormat.peerConnection(livePeer) == "utp")
        #expect(!queuedPeer.isLiveConnection)
        #expect(TorrentDisplayFormat.peerConnection(queuedPeer) == "Queued")
    }
}
