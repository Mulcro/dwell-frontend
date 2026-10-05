import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted with the device's APNs token as a hex string in `object`.
    static let dwellPushToken = Notification.Name("dwellPushToken")
}

/// Receives the APNs device token and shows pushes that arrive while the app
/// is open. The token goes to the session by notification, because the
/// delegate is created by UIKit before the session exists.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .dwellPushToken, object: hex)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// A nudge that lands while Dwell is open still shows, rather than being
    /// swallowed because the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

enum PushRegistration {
    /// Asks APNs for a token when the user has already allowed notifications.
    /// Run on every launch: tokens change, and the backend clears one Apple
    /// reports as dead, so a fresh registration always wins.
    @MainActor
    static func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}
