import Foundation
import Testing
@testable import SweepCore

@Suite struct TorrentMediaTests {
    private func file(_ id: Int, _ path: String, _ length: UInt64, padding: Bool = false) -> TorrentFile {
        TorrentFile(id: id, path: path, length: length, progressBytes: length, isPadding: padding)
    }

    @Test func identifiesMovieInsteadOfArtworkSamplesAndPadding() {
        let media = TorrentMedia(files: [file(0, "cover.jpg", 5_000), file(1, "Movie.Sample.mkv", 30),
            file(2, "Movie.1080p.MKV", 1_000), file(3, "Extras/Interview.mp4", 700), file(4, "pad.mp4", 5_000, padding: true)])
        #expect(media.primaryVideo?.id == 2)
        #expect(media.videos.map(\.id) == [2])
    }

    @Test func episodeOrderIsNaturalAndNeverChoosesALargestEpisode() {
        let media = TorrentMedia(files: [file(0, "Show.S01E10.mp4", 900), file(1, "Show.S01E2.mp4", 100),
            file(2, "Show.S01E1.mp4", 100), file(3, "poster.jpg", 20)])
        #expect(media.isSeries)
        #expect(media.primaryVideo == nil)
        #expect(media.videos.map(\.id) == [2, 1, 0])
        #expect(file(4, "Show.1x02.mkv", 100).isEpisode)
    }

    @Test func collectionsAndNonVideoDownloadsDoNotInventAMainMovie() {
        #expect(TorrentMedia(files: [file(0, "Part One.mp4", 100), file(1, "Part Two.mp4", 80)]).primaryVideo == nil)
        #expect(TorrentMedia(files: [file(0, "cover.jpg", 100), file(1, "audio.mp3", 800)]).videos.isEmpty)
        #expect(TorrentMedia(files: [file(0, "The.Sample.Movie.mp4", 100)]).primaryVideo?.id == 0)
    }

    @Test func partialAndCheckingFilesOpenTheOriginalPayload() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 100).write(to: root.appending(path: "movie.mp4"))
        let complete = file(0, "movie.mp4", 100)
        let partial = TorrentFile(id: 0, path: "movie.mp4", length: 100, progressBytes: 20)
        let torrent = Torrent(name: "Movie", infoHash: "test", downloadDirectory: root.path, state: "live",
                              files: [complete], progressBytes: 100, totalBytes: 100, uploadedBytes: 0,
                              downloadBps: 0, uploadBps: 0, error: nil)
        let original = root.appending(path: "movie.mp4").resolvingSymlinksInPath()
        #expect(TorrentFileLocation.openableFileURL(for: partial, in: torrent, defaultDirectory: "/unused") == original)
        #expect(TorrentFileLocation.openableFileURL(for: partial, in: torrent.updating(state: "initializing"), defaultDirectory: "/unused") == original)
        #expect(TorrentFileLocation.openableFileURL(for: complete, in: torrent, defaultDirectory: "/unused") == original)
        let padding = file(1, "movie.mp4", 100, padding: true)
        #expect(TorrentFileLocation.openableFileURL(for: padding, in: torrent, defaultDirectory: "/unused") == nil)
        #expect(TorrentFileLocation.openableFileURL(for: file(2, "../movie.mp4", 100), in: torrent, defaultDirectory: "/unused") == nil)
        try FileManager.default.removeItem(at: root.appending(path: "movie.mp4"))
        #expect(TorrentFileLocation.openableFileURL(for: complete, in: torrent, defaultDirectory: "/unused") == nil)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        #expect(TorrentFileLocation.openableFileURL(for: partial, in: torrent, defaultDirectory: "/unused") == nil)
    }
}
