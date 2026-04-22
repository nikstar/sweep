import SwiftUI
import Observation
import OSLog
import SweepCore
import SweepRQBitBridge

struct IOSContentView: View {
    @State private var probe = IOSDownloadProbe()

    var body: some View {
        NavigationStack {
            List {
                Section("Transfer") {
                    LabeledContent("State", value: probe.status)
                    LabeledContent("Name", value: probe.torrentName)
                    LabeledContent("Downloaded", value: ByteFormatter.bytes(probe.progressBytes))
                    LabeledContent("Total", value: ByteFormatter.bytes(probe.totalBytes))
                    LabeledContent("Down", value: ByteFormatter.rate(probe.downloadBps))
                    LabeledContent("Up", value: ByteFormatter.rate(probe.uploadBps))
                }

                Section("Destination") {
                    Text(probe.downloadDirectory)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = probe.message {
                    Section("Log") {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(probe.didVerifyDownload ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("Sweep iOS")
            .toolbar {
                Button {
                    probe.start()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            probe.start()
        }
    }
}

@MainActor
@Observable
final class IOSDownloadProbe {
    var status = "Idle"
    var torrentName = "Sample Magnet"
    var progressBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var downloadBps: Double = 0
    var uploadBps: Double = 0
    var message: String?
    var didVerifyDownload = false

    let downloadDirectory: String

    @ObservationIgnored
    private var task: Task<Void, Never>?
    @ObservationIgnored
    private var engine: RqbitEngine?
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.nikstar.sweep.ios", category: "Probe")

    init() {
        downloadDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "SweepDownloads", directoryHint: .isDirectory)
            .path
    }

    deinit {
        task?.cancel()
    }

    func start() {
        task?.cancel()
        didVerifyDownload = false
        task = Task { [downloadDirectory] in
            await run(downloadDirectory: downloadDirectory)
        }
    }

    private func run(downloadDirectory: String) async {
        do {
            let magnet = try sampleMagnet()
            log("SWEEP_IOS_SAMPLE_MAGNET \(magnet)")

            try FileManager.default.createDirectory(
                at: URL(filePath: downloadDirectory, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )

            status = "Starting"
            message = "Creating rqbit engine"
            let engine = try RqbitEngine(downloadDirectory: downloadDirectory)
            self.engine = engine

            message = "Adding sample magnet"
            let addedTorrent = try await engine.addTorrent(
                .magnet(magnet),
                downloadDirectory: downloadDirectory,
                startPaused: false
            )
            update(from: addedTorrent)
            log("SWEEP_IOS_TORRENT_ADDED \(addedTorrent.infoHash)")

            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(2))

                let torrents = try await engine.list()
                guard let torrent = torrents.first(where: { $0.id == addedTorrent.id }) ?? torrents.first else {
                    continue
                }
                update(from: torrent)
                log(
                    "SWEEP_IOS_PROGRESS state=\(torrent.statusLabel) progressBytes=\(torrent.progressBytes) totalBytes=\(torrent.totalBytes) downBps=\(torrent.downloadBps)"
                )

                if torrent.progressBytes > 0 || torrent.downloadBps > 0 {
                    didVerifyDownload = true
                    message = "Verified rqbit download activity in iOS simulator"
                    log("SWEEP_IOS_DOWNLOAD_VERIFIED progressBytes=\(torrent.progressBytes)")
                    return
                }
            }
        } catch {
            status = "Error"
            message = error.localizedDescription
            log("SWEEP_IOS_DOWNLOAD_FAILED \(error.localizedDescription)")
        }
    }

    private func update(from torrent: Torrent) {
        torrentName = torrent.name
        progressBytes = torrent.progressBytes
        totalBytes = torrent.totalBytes
        downloadBps = torrent.downloadBps
        uploadBps = torrent.uploadBps
        status = torrent.statusLabel
        if message == nil || didVerifyDownload == false {
            message = torrent.error
        }
    }

    private func sampleMagnet() throws -> String {
        guard let url = Bundle.main.url(forResource: "magnet", withExtension: "txt") else {
            throw IOSProbeError(message: "magnet.txt is missing from the app bundle")
        }
        let magnet = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard magnet.lowercased().hasPrefix("magnet:") else {
            throw IOSProbeError(message: "magnet.txt does not contain a magnet link")
        }
        return magnet
    }

    private func log(_ message: String) {
        print(message)
        logger.notice("\(message, privacy: .public)")
    }
}

private struct IOSProbeError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
