import SwiftUI
import UIKit

/// Presents a screen above whatever is already showing. A push can be tapped
/// with the feed, a sheet, or Settings open, and a SwiftUI cover attached
/// lower down can't present while another one is up.
@MainActor
enum TopPresenter {
    static func present<Content: View>(_ content: (_ close: @escaping () -> Void) -> Content) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        else { return }
        var top = root
        while let next = top.presentedViewController { top = next }

        weak var hostRef: UIViewController?
        let host = UIHostingController(rootView: content { hostRef?.dismiss(animated: true) })
        hostRef = host
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: true)
    }
}
