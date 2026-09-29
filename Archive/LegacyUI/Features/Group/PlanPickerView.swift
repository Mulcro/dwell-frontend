import SwiftUI

/// The destination behind Group Setup's "Change ›". Backed by the mock
/// PlanService (§3.4) — reimplementing `listPlans` against a real YouVersion
/// plans endpoint is the only change needed later.
///
/// DESIGN: invented — no Figma source.
struct PlanPickerView: View {
    var onBack: () -> Void = {}
    var onPick: (PlanChallenge) -> Void = { _ in }
    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var plans: Loadable<[PlanChallenge]> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(onLeading: onBack)

            VStack(alignment: .leading, spacing: Space.sm) {
                Eyebrow("Step 1 of 3")
                Text("What are you reading?")
                    .font(.dwellTitle)
                    .foregroundStyle(t.textPrimary)
            }
            .padding(.bottom, Space.xl)

            LoadableView(state: plans, retry: { Task { await load() } }) { list in
                ScrollView {
                    VStack(spacing: Space.md) {
                        ForEach(list) { plan in
                            Button { onPick(plan) } label: { planRow(plan) }
                                .buttonStyle(.plain)
                        }

                        Panel(dashed: true) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Write our own challenge")
                                    .font(.dwellBodyMd)
                                    .foregroundStyle(t.textPrimary)
                                Text("A verse a day, or your own list. Coming soon.")
                                    .font(.dwellCaption)
                                    .foregroundStyle(t.textSecondary)
                            }
                        }
                    }
                    .padding(.bottom, Space.xl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .task { await load() }
    }

    private func planRow(_ plan: PlanChallenge) -> some View {
        Panel {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.dwellBodyMd)
                        .foregroundStyle(t.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(plan.dayCount) days · \(plan.sourceType == .youversionPlan ? "YouVersion plan" : "Custom")")
                        .font(.dwellCaption)
                        .foregroundStyle(t.textSecondary)
                }
                Spacer()
                Text("›").foregroundStyle(t.textTertiary)
            }
        }
    }

    private func load() async {
        plans = .loading
        do { plans = .loaded(try await session.api.listPlans()) }
        catch { plans = .failed(error.localizedDescription) }
    }
}
