import SwiftUI

/// Name, plan, frequency, threshold. The creator sets all of it solo — no
/// group vote (MVP Spec §2).
struct GroupSetupView: View {
    let planId: UUID
    var onBack: () -> Void = {}
    var onCreated: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dwell) private var t

    @State private var name = ""
    @State private var plan: PlanChallenge?
    @State private var frequency: Frequency = .daily
    @State private var threshold: Double = 50
    @State private var autoSkip: Double = 3
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DwellNavBar(onLeading: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("Step 2 of 3")
                        Text("Set the rhythm")
                            .font(.dwellTitle)
                            .foregroundStyle(t.textPrimary)
                    }

                    FieldGroup(label: "Group name") {
                        TextField("Sunday Crew", text: $name)
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                            .textFieldStyle(.plain)
                    }

                    FieldGroup(label: "Plan",
                               footnote: "From YouVersion plans. Custom challenges are coming.") {
                        HStack {
                            Text(plan?.title ?? "Loading…")
                                .font(.dwellBodyMd)
                                .foregroundStyle(t.textPrimary)
                            Spacer()
                            Button("Change", action: onBack)
                                .font(.dwellFootnoteMd)
                                .foregroundStyle(t.accent)
                        }
                    }

                    frequencySection
                    thresholdSection
                    autoSkipSection
                }
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)

            if let error {
                Text(error)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
                    .padding(.bottom, Space.sm)
            }

            DwellButton(title: creating ? "Creating…" : "Next — invite people") {
                Task { await create() }
            }
            .disabled(creating || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.lg)
        .task {
            plan = try? await session.api.getPlan(id: planId)
        }
    }

    /// All three cadences are live — the backend resolves which local day it
    /// is from the group's timezone.
    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Eyebrow("Frequency")
            HStack(spacing: Space.sm) {
                ForEach(Frequency.allCases) { option in
                    PillToggle(title: option.label, selected: frequency == option) {
                        frequency = option
                    }
                }
            }
            Text(frequency.detail + " Days are counted in \(friendlyZone).")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
        }
    }

    /// The group's day boundaries follow whoever created it.
    private var friendlyZone: String {
        TimeZone.current.identifier
            .components(separatedBy: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? "your time zone"
    }

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Eyebrow("Unlock threshold")
                Spacer()
                Text("\(Int(threshold))%")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.accent)
            }
            Slider(value: $threshold, in: 25...100, step: 25)
            Text("Half the group has to post before anyone can read the day. Raise it for a tighter group, lower it if people travel.")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(3)
        }
    }

    /// `auto_skip_after_days` — group-configurable in the schema but never
    /// surfaced in the Figma. DESIGN: invented — no Figma source.
    private var autoSkipSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Eyebrow("Skip a stuck day after")
                Spacer()
                Text("\(Int(autoSkip)) days")
                    .font(.dwellBodyMd)
                    .foregroundStyle(t.accent)
            }
            Slider(value: $autoSkip, in: 1...7, step: 1)
            Text("If a day never reaches the threshold, the group moves on rather than staying frozen on it.")
                .font(.dwellCaption)
                .foregroundStyle(t.textSecondary)
                .lineSpacing(3)
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            _ = try await session.api.createGroup(
                name: name.trimmingCharacters(in: .whitespaces),
                planChallengeId: planId,
                frequency: frequency,
                timezone: TimeZone.current.identifier,
                catchUpThresholdPct: Int(threshold),
                autoSkipAfterDays: Int(autoSkip))
            onCreated()
        } catch { self.error = error.localizedDescription }
    }
}

/// Label + bordered field + optional helper line.
struct FieldGroup<Content: View>: View {
    let label: String
    var footnote: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow(label)
            content
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
            if let footnote {
                Text(footnote)
                    .font(.dwellCaption)
                    .foregroundStyle(t.textSecondary)
            }
        }
    }
}
