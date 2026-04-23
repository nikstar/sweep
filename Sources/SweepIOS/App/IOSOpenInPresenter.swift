import UIKit

@MainActor
final class IOSOpenInPresenter: NSObject, @preconcurrency UIDocumentInteractionControllerDelegate {
    static let shared = IOSOpenInPresenter()

    private var documentController: UIDocumentInteractionController?

    func present(url: URL) -> Bool {
        guard
            let viewController = UIApplication.shared.topMostViewController,
            let view = viewController.view
        else {
            return false
        }

        let documentController = UIDocumentInteractionController(url: url)
        documentController.delegate = self
        self.documentController = documentController

        let anchor = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        let didPresent = documentController.presentOptionsMenu(from: anchor, in: view, animated: true)
        if !didPresent {
            self.documentController = nil
        }
        return didPresent
    }

    func documentInteractionControllerDidDismissOptionsMenu(
        _ controller: UIDocumentInteractionController
    ) {
        if controller === documentController {
            documentController = nil
        }
    }

    func documentInteractionControllerDidEndPreview(
        _ controller: UIDocumentInteractionController
    ) {
        if controller === documentController {
            documentController = nil
        }
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
