import Foundation

/// Where the signed-in user's avatar URL lives.
///
/// `public.users` has no avatar column, so there's nowhere on the server to
/// put it — this keeps it on the device for the current user only. It follows
/// that **group-mates have no avatars**: their rows carry name, language and
/// timezone, nothing more. Showing everyone's picture needs a `users.avatar_url`
/// column populated by the sign-in bridge (see FOR-BACKEND.md).
@MainActor
final class AvatarStore {
    static let shared = AvatarStore()

    private let key = "profile.avatarURL"

    private init() {}

    var url: URL? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return URL(string: raw)
    }

    func remember(_ url: URL?) {
        guard let url else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
