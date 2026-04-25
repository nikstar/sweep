import AVFoundation
import CoreLocation
import Foundation
import SweepCore
import UIKit

@MainActor
final class IOSBackgroundDownloadService {
    private let settings = IOSBackgroundDownloadSettings()
    private var configuredMode: IOSBackgroundDownloadMode
    private var modeRunner: IOSBackgroundDownloadModeRunner
    private var monitorTask: Task<Void, Never>?

    init() {
        let mode = settings.mode
        self.configuredMode = mode
        self.modeRunner = Self.makeRunner(for: mode, settings: settings)
    }

    func prepareConfiguredMode() async {
        await applyConfiguredMode()
    }

    func startIfNeeded(store: TorrentStore) {
        guard settings.isEnabled, isBackgroundNeeded(for: store.torrents) else {
            stop()
            return
        }

        Task { @MainActor in
            await applyConfiguredMode()
            guard modeRunner.start() else { return }
            startMonitoring(store: store)
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        modeRunner.stop()
    }

    private func applyConfiguredMode() async {
        let mode = settings.mode
        if mode != configuredMode {
            modeRunner.stop()
            modeRunner = Self.makeRunner(for: mode, settings: settings)
            configuredMode = mode
        }

        guard await modeRunner.prepare() else {
            guard configuredMode != .audio else { return }
            modeRunner.stop()
            settings.mode = .audio
            configuredMode = .audio
            modeRunner = Self.makeRunner(for: .audio, settings: settings)
            _ = await modeRunner.prepare()
            return
        }
    }

    private func startMonitoring(store: TorrentStore) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor in
            while !Task.isCancelled {
                await store.refreshNow()
                guard isBackgroundNeeded(for: store.torrents) else {
                    stop()
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
            }
        }
    }

    private func isBackgroundNeeded(for torrents: [Torrent]) -> Bool {
        torrents.contains { torrent in
            guard torrent.desiredState == .running, torrent.error == nil else { return false }

            if torrent.totalBytes == 0 || torrent.progress < 1 {
                return true
            }

            return settings.allowsBackgroundSeeding
        }
    }

    private static func makeRunner(
        for mode: IOSBackgroundDownloadMode,
        settings: IOSBackgroundDownloadSettings
    ) -> IOSBackgroundDownloadModeRunner {
        switch mode {
        case .audio:
            IOSAudioBackgroundMode()

        case .location:
            IOSLocationBackgroundMode(settings: settings)
        }
    }
}

private enum IOSBackgroundDownloadMode: String {
    case audio
    case location
}

private final class IOSBackgroundDownloadSettings {
    private enum Key {
        static let isEnabled = "IOSBackgroundDownloadEnabled"
        static let mode = "IOSBackgroundDownloadMode"
        static let allowsBackgroundSeeding = "IOSBackgroundDownloadAllowsSeeding"
        static let showsLocationIndicator = "IOSBackgroundDownloadShowsLocationIndicator"
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

    var mode: IOSBackgroundDownloadMode {
        get {
            guard let rawMode = defaults.string(forKey: Key.mode),
                  let mode = IOSBackgroundDownloadMode(rawValue: rawMode)
            else {
                return .audio
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.mode)
        }
    }

    var allowsBackgroundSeeding: Bool {
        get { defaults.bool(forKey: Key.allowsBackgroundSeeding) }
        set { defaults.set(newValue, forKey: Key.allowsBackgroundSeeding) }
    }

    var showsLocationIndicator: Bool {
        get { defaults.bool(forKey: Key.showsLocationIndicator) }
        set { defaults.set(newValue, forKey: Key.showsLocationIndicator) }
    }
}

@MainActor
private protocol IOSBackgroundDownloadModeRunner: AnyObject {
    var isRunning: Bool { get }
    func prepare() async -> Bool
    func start() -> Bool
    func stop()
}

@MainActor
private final class IOSAudioBackgroundMode: NSObject, IOSBackgroundDownloadModeRunner {
    private var player: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var renewalTask: Task<Void, Never>?

    var isRunning: Bool {
        (player?.isPlaying ?? false) || backgroundTask != .invalid || renewalTask != nil
    }

    func prepare() async -> Bool {
        true
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        renewBackgroundTask()
        return true
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        renewalTask?.cancel()
        renewalTask = nil
        endBackgroundTask()
        stopAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            notification.name == AVAudioSession.interruptionNotification,
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: typeValue) == .ended
        else {
            return
        }

        _ = playAudio()
    }

    private func renewBackgroundTask() {
        renewalTask?.cancel()
        renewalTask = Task { @MainActor in
            while !Task.isCancelled {
                guard playAudio() else {
                    stop()
                    return
                }

                endBackgroundTask()
                backgroundTask = UIApplication.shared.beginBackgroundTask(
                    withName: "Sweep background downloads"
                ) { [weak self] in
                    Task { @MainActor in
                        self?.renewBackgroundTask()
                    }
                }

                stopAudio()
                guard backgroundTask != .invalid else { continue }

                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
            }
        }
    }

    private func playAudio() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try player ?? makePlayer()
            self.player = player
            player.play()
            return true
        } catch {
            return false
        }
    }

    private func stopAudio() {
        player?.stop()
    }

    private func makePlayer() throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: Self.keepAliveAudioData)
        player.volume = 0.01
        player.numberOfLoops = -1
        return player
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private static let keepAliveAudioData: Data = {
        let sampleRate = 8_000
        let sampleCount = sampleRate
        var pcm = Data()
        pcm.reserveCapacity(sampleCount * 2)

        for sampleIndex in 0..<sampleCount {
            let phase = 2 * Double.pi * 440 * Double(sampleIndex) / Double(sampleRate)
            let sample = Int16(sin(phase) * Double(Int16.max) * 0.05)
            pcm.appendLittleEndian(sample)
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(pcm.count))
        data.append(pcm)
        return data
    }()
}

@MainActor
private final class IOSLocationBackgroundMode: NSObject, IOSBackgroundDownloadModeRunner, CLLocationManagerDelegate, @unchecked Sendable {
    private let settings: IOSBackgroundDownloadSettings
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private(set) var isRunning = false

    init(settings: IOSBackgroundDownloadSettings) {
        self.settings = settings
        super.init()
        locationManager.delegate = self
    }

    func prepare() async -> Bool {
        var status = locationManager.authorizationStatus
        guard status == .notDetermined else {
            return status != .denied && status != .restricted
        }

        locationManager.requestAlwaysAuthorization()

        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
        }

        status = locationManager.authorizationStatus
        return status != .denied && status != .restricted && status != .notDetermined
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        isRunning = startLocationUpdates()
        return isRunning
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        isRunning = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }

        Task { @MainActor in
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        }
    }

    private func startLocationUpdates() -> Bool {
        let status = locationManager.authorizationStatus
        guard status != .denied && status != .restricted && status != .notDetermined else {
            return false
        }

        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.showsBackgroundLocationIndicator = settings.showsLocationIndicator
        locationManager.startUpdatingLocation()
        return true
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { bytes in
            append(contentsOf: bytes)
        }
    }
}
