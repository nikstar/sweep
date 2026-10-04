import UIKit
import UniformTypeIdentifiers

@MainActor
final class IOSOpenInPresenter {
    static let shared = IOSOpenInPresenter()

    func present(url: URL) -> Bool {
        guard
            let viewController = UIApplication.shared.topMostViewController,
            let view = viewController.view
        else {
            return false
        }

        // Sweep's Documents are exposed through iOS's local file provider by the
        // UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace plist keys.
        // Offer the original growing file to readers that request open-in-place.
        // A receiving app can still choose a copy (e.g. a messaging attachment).
        let provider = NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: .openInPlace,
                                            visibility: .all) { completion in
            completion(url, true, nil)
            return nil
        }
        let activityViewController = UIActivityViewController(
            activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider]))

        let anchor = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        activityViewController.popoverPresentationController?.sourceView = view
        activityViewController.popoverPresentationController?.sourceRect = anchor

        viewController.present(activityViewController, animated: true)
        return true
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController?
            .topMostPresentedViewController
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow } ?? windows.first
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topMostPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topMostPresentedViewController
        }

        return self
    }
}
