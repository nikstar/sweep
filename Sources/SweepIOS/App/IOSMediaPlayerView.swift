import AVKit
import Observation
import SwiftUI

struct IOSMediaFile: Identifiable {
    let url: URL
    let name: String
    let isIncomplete: Bool
    var id: URL { url }
}

struct IOSMediaPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let file: IOSMediaFile
    @State private var playback = IOSMediaPlayback()
    @State private var attempt = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let message = playback.failure {
                    ContentUnavailableView {
                        Label(file.isIncomplete ? "Video Not Ready" : "Unable to Play Video", systemImage: "play.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again", systemImage: "arrow.clockwise") { attempt = UUID() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        Button("Open in Another App…", systemImage: "square.and.arrow.up") {
                            if !IOSOpenInPresenter.shared.present(url: file.url) {
                                playback.failure = "The sharing menu could not be opened. Close the player and try again."
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else if let player = playback.player {
                    IOSNativePlayer(player: player)
                } else {
                    ProgressView("Opening video…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if file.isIncomplete, playback.failure == nil {
                        Button("Reload Video", systemImage: "arrow.clockwise") { attempt = UUID() }
                    }
                    Button("Open in Another App", systemImage: "square.and.arrow.up") {
                        if !IOSOpenInPresenter.shared.present(url: file.url) {
                            playback.failure = "The sharing menu could not be opened. Close the player and try again."
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: attempt) { await playback.open(file) }
        .onDisappear { playback.stop() }
    }
}

@MainActor @Observable
private final class IOSMediaPlayback {
    private(set) var player: AVPlayer?
    var failure: String?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var failureObservation: NSObjectProtocol?
    @ObservationIgnored private var generation = UUID()

    func open(_ file: IOSMediaFile) async {
        let position = player?.currentTime()
        stop()
        failure = nil
        let generation = self.generation
        let message = file.isIncomplete
            ? "Some video data may still be missing. Try again as the download progresses, or open the file in a compatible player."
            : "This video could not be played here. Try again or open it in a compatible app installed on your iPhone."
        do {
            // Always read the engine's original payload; retry makes a fresh asset
            // so AVFoundation can inspect newly downloaded headers and chunks.
            let asset = AVURLAsset(url: file.url)
            let playable = try await asset.load(.isPlayable)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            guard playable else { failure = message; return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try session.setActive(true)
            let item = AVPlayerItem(asset: asset)
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    guard self?.generation == generation else { return }
                    self?.failure = message
                }
            }
            // A partial file can open successfully and later fail at a missing chunk.
            failureObservation = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.generation == generation else { return }
                    self?.failure = message
                }
            }
            let player = AVPlayer(playerItem: item)
            // Playback is foreground-only; background transfer audio owns its own lifecycle.
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            self.player = player
            if let position, position.seconds.isFinite, position.seconds > 0 {
                await player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            player.play()
        } catch is CancellationError {
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            failure = "\(message)\n\n\(error.localizedDescription)"
        }
    }

    func stop() {
        generation = UUID()
        player?.pause()
        player = nil
        statusObservation = nil
        if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
        failureObservation = nil
        if UIApplication.shared.applicationState == .active {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private struct IOSNativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
