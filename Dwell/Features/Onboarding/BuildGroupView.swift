import SwiftUI

/// Figma: "Build New Group" — name it, pick a challenge.
struct BuildGroupView: View {
    var onBack: () -> Void = {}
    var onNext: (String, PlanChallenge) -> Void = { _, _ in }

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t
    @State private var name = ""
    @State private var plans: Loadable<[PlanChallenge]> = .idle
    @State private var selected: PlanChallenge?
    @State private var search = ""
    /// The plan whose detail screen (Figma 02b) is open.
    @State private var detailPlan: PlanChallenge?

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 280, fadeFrom: 0.2)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeader(progress: 0.56, onBack: onBack)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        Text("Build a new group.")
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)

                        DwellField(label: "Group Name",
                                   placeholder: "ex: Sunday Crew",
                                   description: "You can change this later.",
                                   text: $name)

                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("Pick a Challenge")
                                .font(.dwellSmallMd)
                                .foregroundStyle(t.textPrimary)

                            searchField

                            LoadableView(state: plans, retry: { Task { await load() } }) { list in
                                VStack(spacing: Space.md) {
                                    ForEach(filtered(list)) { plan in
                                        planCard(plan)
                                    }
                                    if filtered(list).isEmpty {
                                        Text("No plans match “\(search)”.")
                                            .font(.dwellSmall)
                                            .foregroundStyle(t.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                PrimaryButton(title: "Continue",
                              enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && selected != nil) {
                    if let selected {
                        onNext(name.trimmingCharacters(in: .whitespaces), selected)
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
        .task { await load() }
        .fullScreenCover(item: $detailPlan) { plan in
            PlanDetailView(plan: plan,
                           onClose: { detailPlan = nil },
                           onStart: {
                               Haptics.select()
                               selected = $0
                               detailPlan = nil
                           })
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(t.textSecondary)
            TextField("Search Plans", text: $search)
                .font(.dwellBody)
                .textFieldStyle(.plain)
                .foregroundStyle(t.textPrimary)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 14)
        .background(t.surfaceRaised)
        .clipShape(Capsule())
    }

    /// Image on top, title in the middle, Select and Details below.
    /// Tapping the card selects too; Details is the only way into the
    /// detail screen, so browsing never changes the choice by accident.
    /// Image on top, title in the middle, Select and Details below.
    /// Tapping the card selects too; Details is the only way into the
    /// detail screen, so browsing never changes the choice by accident.
    private func planCard(_ plan: PlanChallenge) -> some View {
        let isSelected = selected?.id == plan.id
        return VStack(spacing: 0) {
            PlanCover(title: plan.title,
                      imageURL: plan.imagePath.flatMap { session.api.planImageURL(path: $0) })
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(spacing: Space.sm) {
                Text("\(plan.dayCount) Days")
                    .font(.dwellCaptionMd)
                    .foregroundStyle(t.textSecondary)

                Text(plan.title)
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.xl) {
                    Button {
                        Haptics.select()
                        selected = plan
                    } label: {
                        Text(isSelected ? "Selected" : "Select")
                            .font(.dwellCaptionMd)
                            .foregroundStyle(isSelected ? t.onInk : t.textPrimary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(isSelected ? t.ink : .clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(isSelected ? .clear : t.borderStrong, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressScale())

                    Button {
                        Haptics.tap()
                        detailPlan = plan
                    } label: {
                        Text("Details")
                            .font(.dwellCaptionMd)
                            .foregroundStyle(t.textPrimary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .overlay(
                                Capsule().strokeBorder(t.borderStrong, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressScale())
                }
                .padding(.top, Space.sm)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity)
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? t.ink : t.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture {
            Haptics.select()
            selected = plan
        }
    }

    private func filtered(_ list: [PlanChallenge]) -> [PlanChallenge] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func load() async {
        plans = .loading
        do {
            let list = try await session.api.listPlans()
            plans = .loaded(list)
            selected = selected ?? list.first
            // DWELL_PLAN_DETAIL=1 opens the first plan's detail straight
            // away, for screenshots — same idea as DWELL_REFLECT on Home.
            if ProcessInfo.processInfo.environment["DWELL_PLAN_DETAIL"] == "1" {
                detailPlan = list.first
            }
        } catch {
            plans = .failed(error.localizedDescription)
        }
    }
}

#Preview { BuildGroupView() }
