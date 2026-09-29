import Foundation

/// Reads the Supabase connection out of the build configuration.
///
/// Values come from `Config/Secrets.xcconfig` (gitignored) via the generated
/// Info.plist. `Config/Secrets.example.xcconfig` is the committed template.
enum DwellConfig {

    static var supabaseURL: URL? {
        guard let raw = string("SUPABASE_URL"), let url = URL(string: raw) else { return nil }
        return url
    }

    static var publishableKey: String? {
        guard let key = string("SUPABASE_PUBLISHABLE_KEY"), !key.isEmpty else { return nil }
        return key
    }

    /// YouVersion's PKCE public client id. Unlike the Supabase key this one
    /// genuinely belongs on the device — YouVersion issues no client secret.
    static var youVersionAppKey: String? { string("YOUVERSION_APP_KEY") }

    /// True once both halves are present, which is what decides whether the
    /// app talks to Supabase or stays on the mock.
    static var isConfigured: Bool { supabaseURL != nil && publishableKey != nil }

    /// A publishable key is safe on a client; a secret key is not. Catching
    /// this at launch beats discovering it in a shipped build.
    static var keyLooksLikeASecret: Bool {
        (publishableKey ?? "").hasPrefix("sb_secret_")
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
