import SwiftUI

/// Drives the real app through the real router by reseeding the mock backend.
/// This replaces the old screen gallery: you pick a *state*, not a screen.
struct ScenarioSwitcher: View {
    @Environment(SessionStore.self) private var session
    @Environment(MockDwellAPI.self) private var mock
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scenario") private var current = MockDwellAPI.Scenario.dayOpenNotPosted.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Jump the app to a state") {
                    ForEach(MockDwellAPI.Scenario.allCases) { scenario in
                        Button {
                            current = scenario.rawValue
                            mock.load(scenario)
                            Task {
                                await session.bootstrap()
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(scenario.rawValue)
                                Spacer()
                                if current == scenario.rawValue {
                                    Text("✓").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Reference") {
                    LabeledContent("Plan", value: "Anchored — 7 days")
                    LabeledContent("Threshold", value: "50%")
                    LabeledContent("Backend", value: "MockDwellAPI")
                }
            }
            .navigationTitle("Scenarios")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
