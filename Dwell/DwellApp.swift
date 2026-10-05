import SwiftUI

@main
struct DwellApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: SessionStore
    /// Only present on the mock backend — drives the debug scenario switcher.
    @State private var mock: MockDwellAPI?

    @MainActor
    init() {
        YouVersionReader.configure(appKey: DwellConfig.youVersionAppKey)


        // Real backend when Secrets.xcconfig carries a publishable key,
        // the mock otherwise. DWELL_FORCE_MOCK=1 pins it to the mock.
        let forceMock = ProcessInfo.processInfo.environment["DWELL_FORCE_MOCK"] == "1"

        if !forceMock,
           DwellConfig.isConfigured,
           !DwellConfig.keyLooksLikeASecret,
           let url = DwellConfig.supabaseURL,
           let key = DwellConfig.publishableKey {
            _mock = State(initialValue: nil)
            _session = State(initialValue: SessionStore(
                api: SupabaseDwellAPI(url: url, publishableKey: key)))
        } else {
            if DwellConfig.keyLooksLikeASecret {
                assertionFailure("SUPABASE_PUBLISHABLE_KEY looks like a secret key. That bypasses RLS.")
            }
            let named = ProcessInfo.processInfo.environment["DWELL_SCENARIO"]
            let scenario = MockDwellAPI.Scenario.allCases
                .first { $0.rawValue == named } ?? .dayOpenNotPosted
            let api = MockDwellAPI(scenario: scenario)
            _mock = State(initialValue: api)
            _session = State(initialValue: SessionStore(api: api))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(mock)
        }
    }
}
