import UIKit
import UserNotifications

/// What a tapped reply push asks the app to open (KAN-22 payload).
struct PushRoute: Equatable {
    let groupId: UUID
    let reflectionId: UUID
    let commentId: UUID?
}

/// Holds a tapped push until the app can act on it. On a cold start the tap
/// arrives before anyone is signed in or the group has loaded, so RootView
/// picks it up once Home is showing.
@MainActor @Observable
final class PushInbox {
    static let shared = PushInbox()
    var pending: PushRoute?
}

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

    /// A tap on a reply push. Other types (the nudge) just open the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard info["type"] as? String == "reply",
              let group = (info["group_id"] as? String).flatMap(UUID.init(uuidString:)),
              let reflection = (info["reflection_id"] as? String).flatMap(UUID.init(uuidString:))
        else { return }
        let comment = (info["comment_id"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            PushInbox.shared.pending = PushRoute(groupId: group, reflectionId: reflection,
                                                 commentId: comment)
        }
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
