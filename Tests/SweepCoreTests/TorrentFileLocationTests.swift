import Foundation
import Testing
@testable import SweepCore

@Suite
struct TorrentFileLocationTests {
    @Test
    func revealsActualPayloadRootInsteadOfAppendingDisplayName() {
        func torrent(_ paths: [String]) -> Torrent {
            Torrent(name: "Display Name", infoHash: "test", downloadDirectory: "/tmp/Downloads/Album",
                    state: "paused", files: paths.enumerated().map {
                        TorrentFile(id: $0.offset, path: $0.element, length: 4, progressBytes: 4)
                    }, progressBytes: 8, totalBytes: 8, uploadedBytes: 0,
                    downloadBps: 0, uploadBps: 0, error: nil)
        }
        func item(_ paths: [String]) -> String {
            TorrentFileLocation.expectedItemURL(for: torrent(paths), defaultDirectory: "/unused")
                .resolvingSymlinksInPath().path
        }
        let base = URL(filePath: "/tmp/Downloads/Album").resolvingSymlinksInPath().path
        #expect(item(["01.mp3", "02.mp3"]) == base)
        #expect(item(["Existing/01.mp3", "Existing/02.mp3"]) == base + "/Existing")
        #expect(item(["Disc 1/01.mp3", "Disc 2/02.mp3"]) == base)
        #expect(item(["Different Filename.mp3"]) == base + "/Different Filename.mp3")
        #expect(item(["../outside", "02.mp3"]) == base)
    }

    @Test
    func resolvesNestedFilesAndRejectsPathsOutsideDownloadDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let download = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: download.appending(path: "Album"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = download.appending(path: "Album/Track.txt")
        try Data("test".utf8).write(to: fileURL)
        let torrent = Torrent(name: "Album", infoHash: "test", downloadDirectory: download.path, state: "live",
                              progressBytes: 4, totalBytes: 4, uploadedBytes: 0,
                              downloadBps: 0, uploadBps: 0, error: nil)
        func file(_ path: String) -> TorrentFile { TorrentFile(id: 0, path: path, length: 4, progressBytes: 4) }
        let snapshot = try #require(TorrentFileLocation.fileSnapshot(for: file("Album/Track.txt"), in: torrent, defaultDirectory: "/unused"))
        #expect(snapshot.url == fileURL.resolvingSymlinksInPath())
        #expect(snapshot.isOpenable)
        #expect(TorrentFileLocation.snapshot(for: torrent, defaultDirectory: "/unused").displayKind == "Folder")
        for path in ["../secret", "/etc/passwd", "Album/../../secret", "C:\\secret", ".", ""] {
            #expect(TorrentFileLocation.fileURL(for: file(path), in: torrent, defaultDirectory: "/unused") == nil)
        }
        let outside = root.appending(path: "secret")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: download.appending(path: "link"), withDestinationURL: outside)
        #expect(TorrentFileLocation.fileURL(for: file("link"), in: torrent, defaultDirectory: "/unused") == nil)
    }
}
