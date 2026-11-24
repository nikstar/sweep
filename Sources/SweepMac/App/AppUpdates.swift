import Combine
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdates {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()

    init() {
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &subscriptions)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
