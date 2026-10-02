import Foundation

/// Caches signed avatar URLs across launches.
///
/// The `avatars` bucket is private, so every picture needs a signed URL — and
/// signing is a network round trip. Without a cache, a cold start renders
/// initials for everyone until those requests come back, then swaps them for
/// faces: a visible flicker on a screen the user has already seen.
///
/// Keyed by `avatar_path`, so a replaced picture gets a new key and the old
/// entry simply goes unused. Entries carry their own expiry because signed
/// URLs stop working after 24 hours.
@MainActor
final class AvatarStore {
    static let shared = AvatarStore()

    private let signedKey = "avatars.signed"
    private let legacyKey = "profile.avatarURL"

    private struct Entry: Codable {
        let url: URL
        let expires: Date
    }

    private var cache: [String: Entry] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: signedKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = decoded
        }
        prune()
    }

    /// A still-valid signed URL for this object key, if we have one.
    func signed(for path: String) -> URL? {
        guard let entry = cache[path], entry.expires > .now else { return nil }
        return entry.url
    }

    /// Stored a little shy of the real expiry so a URL is never handed out in
    /// the last moments of its life.
    func remember(_ url: URL, for path: String, lifetime: TimeInterval = 60 * 60 * 24) {
        cache[path] = Entry(url: url, expires: .now.addingTimeInterval(lifetime - 300))
        persist()
    }

    /// Your own picture as the identity provider gave it, from before
    /// `users.avatar_url` existed. Kept only as a last-resort fallback.
    var url: URL? {
        UserDefaults.standard.string(forKey: legacyKey).flatMap(URL.init(string:))
    }

    func remember(_ url: URL?) {
        guard let url else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: legacyKey)
    }

    func clear() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: signedKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private func prune() {
        let before = cache.count
        cache = cache.filter { $0.value.expires > .now }
        if cache.count != before { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: signedKey)
    }
}
