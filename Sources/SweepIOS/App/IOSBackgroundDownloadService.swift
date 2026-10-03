import AVFoundation
import CoreLocation
import Foundation
import Observation
import OSLog
import SweepCore
import UIKit

@MainActor @Observable
final class IOSBackgroundDownloadService {
    var isEnabled = UserDefaults.standard.object(forKey: "IOSBackgroundDownloadEnabled") as? Bool ?? true {
        didSet {
            settings.isEnabled = isEnabled
            refreshCurrentState()
        }
    }
    private(set) var status = "Ready when Sweep is in the background"
    private(set) var lastError: String?
    private(set) var lastCheckAt: Date?
    var modeName: String { configuredMode == .audio ? "Silent audio" : "Location" }

    @ObservationIgnored private let settings = IOSBackgroundDownloadSettings()
    @ObservationIgnored private var configuredMode: IOSBackgroundDownloadMode
    @ObservationIgnored private var runner: IOSBackgroundDownloadModeRunner
    @ObservationIgnored private weak var store: TorrentStore?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var needsBackground = false
    @ObservationIgnored private var retryAfter = Date.distantPast
    private let logger = Logger(subsystem: "me.nikstar.sweep.ios", category: "BackgroundExecution")

    init() {
        let settings = IOSBackgroundDownloadSettings()
        configuredMode = settings.mode
        runner = Self.makeRunner(mode: settings.mode, settings: settings)
    }

    func sceneChanged(store: TorrentStore, needsBackground: Bool) {
        self.needsBackground = needsBackground
        refresh(store: store)
    }

    func refresh(store: TorrentStore) {
        self.store = store
        lastCheckAt = .now
        refreshCurrentState()
    }

    func retry() {
        stop()
        retryAfter = .distantPast
        lastError = nil
        refreshCurrentState()
    }

    private func refreshCurrentState() {
        guard let store else { return }
        let hasWork = store.torrents.contains { torrent in
            torrent.desiredState == .running && torrent.error == nil
                && (torrent.totalBytes == 0 || torrent.progress < 1
                    || torrent.state == "initializing" || torrent.state == "restoring"
                    || settings.allowsBackgroundSeeding)
        }
        guard isEnabled, needsBackground, hasWork else {
            stop()
            if !isEnabled { setStatus("Off") }
            else if !hasWork { setStatus("Idle · No active downloads") }
            else { setStatus("Ready when Sweep is in the background") }
            return
        }
        if runner.isRunning {
            setStatus(runner.status)
            lastError = runner.problem
            return
        }
        guard startTask == nil, Date.now >= retryAfter else { return }
        generation += 1
        let request = generation
        setStatus("Starting \(modeName.lowercased())")
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var prepared = await runner.prepare()
            // An async authorization response must never restart a session after foregrounding.
            guard !Task.isCancelled, request == generation, needsBackground else { return }
            if !prepared, configuredMode == .location {
                runner.stop()
                configuredMode = .audio
                settings.mode = .audio
                runner = Self.makeRunner(mode: .audio, settings: settings)
                prepared = await runner.prepare()
            }
            guard !Task.isCancelled, request == generation, needsBackground else { return }
            defer { startTask = nil }
            do {
                guard prepared else { throw BackgroundFailure("Background mode could not be prepared.") }
                try runner.start()
                lastError = nil
                setStatus(runner.status)
            } catch {
                lastError = error.localizedDescription
                retryAfter = .now.addingTimeInterval(30)
                setStatus("Background session failed")
                logger.error("Background start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stop() {
        generation += 1
        startTask?.cancel()
        startTask = nil
        runner.stop()
    }

    private func setStatus(_ value: String) {
        guard status != value else { return }
        status = value
        logger.notice("\(value, privacy: .public)")
    }

    private static func makeRunner(mode: IOSBackgroundDownloadMode, settings: IOSBackgroundDownloadSettings) -> IOSBackgroundDownloadModeRunner {
        switch mode {
        case .audio: IOSAudioBackgroundMode()
        case .location: IOSLocationBackgroundMode(settings: settings)
        }
    }
}

@MainActor
private protocol IOSBackgroundDownloadModeRunner: AnyObject {
    var isRunning: Bool { get }
    var status: String { get }
    var problem: String? { get }
    func prepare() async -> Bool
    func start() throws
    func stop()
}

private struct BackgroundFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private final class IOSAudioBackgroundMode: NSObject, IOSBackgroundDownloadModeRunner {
    private var player: AVAudioPlayer?
    private var requested = false
    private var interrupted = false
    private(set) var problem: String?
    var isRunning: Bool { requested && (interrupted || player?.isPlaying == true) }
    var status: String { interrupted ? "Audio interrupted" : (player?.isPlaying == true ? "Silent audio active" : "Stopped") }

    func prepare() async -> Bool { true }

    func start() throws {
        guard !isRunning else { return }
        if !requested {
            NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted),
                name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(mediaServicesReset),
                name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }
        requested = true
        do { try play() }
        catch { stop(); throw error }
    }

    func stop() {
        guard requested else { return }
        requested = false
        interrupted = false
        NotificationCenter.default.removeObserver(self)
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard requested, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            interrupted = true
            player?.pause()
            return
        }
        let options = AVAudioSession.InterruptionOptions(rawValue:
            notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        guard options.contains(.shouldResume) else {
            problem = "Audio was interrupted. Reopen Sweep to prepare a new background session."
            return
        }
        resumeIfRequested()
    }

    @objc private func mediaServicesReset(_ notification: Notification) {
        player = nil
        resumeIfRequested()
    }

    private func resumeIfRequested() {
        guard requested else { return }
        do { try play() }
        catch {
            interrupted = true
            problem = error.localizedDescription
        }
    }

    private func play() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try session.setActive(true)
        if player == nil {
            player = try AVAudioPlayer(data: Self.silence)
            player?.numberOfLoops = -1
        }
        guard player?.play() == true else { throw BackgroundFailure("The silent audio player could not start.") }
        interrupted = false
        problem = nil
    }

    // Actual digital silence, continuously looped. No audible tone and no background-task renewal loop.
    private static let silence: Data = {
        let sampleRate = 8_000
        let pcm = Data(count: sampleRate * 2)
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.appendASCII("WAVEfmt ")
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
private final class IOSLocationBackgroundMode: NSObject, IOSBackgroundDownloadModeRunner, CLLocationManagerDelegate, @unchecked Sendable {
    private let settings: IOSBackgroundDownloadSettings
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private(set) var isRunning = false
    var status: String { isRunning ? "Location updates active" : "Stopped" }
    var problem: String? { nil }

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

        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            locationManager.requestAlwaysAuthorization()
        }

        status = locationManager.authorizationStatus
        return status != .denied && status != .restricted && status != .notDetermined
    }

    func start() throws {
        guard !isRunning else { return }
        isRunning = startLocationUpdates()
        if !isRunning { throw BackgroundFailure("Location permission is unavailable.") }
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
