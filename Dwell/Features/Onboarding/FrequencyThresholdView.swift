import SwiftUI

/// Figma: "Frequency & Threshold". The rhythm, framed around the 4-day finding
/// from the previous screen.
struct FrequencyThresholdView: View {
    var onBack: () -> Void = {}
    var onNext: (Frequency, [Int]?, Int, Int) -> Void = { _, _, _, _ in }

    @Environment(\.dwell) private var t
    @State private var frequency: Frequency = .fourPerWeek
    @State private var customDays: Set<Int> = [1, 3, 5]
    @State private var threshold = 50
    @State private var moveOnAfter = 3

    private var customSummary: String {
        guard !customDays.isEmpty else { return "Pick at least one day." }
        let names = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
        return customDays.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(height: 280, fadeFrom: 0.2)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeader(progress: 0.7, onBack: onBack)

                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("Start where you are, and your group will help you get to 4+ days.")
                                .font(.dwellTitle)
                                .lineSpacing(LineSpacing.title)
                                .foregroundStyle(t.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Life change is not meant to be done alone.")
                                .font(.dwellBody)
                                .foregroundStyle(t.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("Frequency")
                                .font(.dwellSmallMd)
                                .foregroundStyle(t.textPrimary)
                            SegmentedChips(items: Frequency.offered,
                                           label: { $0.label },
                                           selection: $frequency)

                            if frequency == .custom {
                                WeekdayPicker(selected: $customDays)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Text(frequency == .custom ? customSummary : frequency.detail)
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("Unlock Threshold")
                                .font(.dwellSmallMd)
                                .foregroundStyle(t.textPrimary)
                            ThresholdStepper(percent: $threshold)
                            Text("Half the group has to post before anyone can read the day. Raise it for a tighter group, lower it if people travel.")
                                .font(.dwellCaption)
                                .lineSpacing(LineSpacing.small)
                                .foregroundStyle(t.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: Space.md) {
                            Text("Move on after")
                                .font(.dwellSmallMd)
                                .foregroundStyle(t.textPrimary)
                            HStack {
                                Text("\(moveOnAfter) day\(moveOnAfter == 1 ? "" : "s") below the threshold")
                                    .font(.dwellBody)
                                    .foregroundStyle(t.textPrimary)
                                Spacer()
                                Stepper("", value: $moveOnAfter, in: 1...7)
                                    .labelsHidden()
                            }
                            Text("If a day never fills, the group moves on rather than staying stuck on it.")
                                .font(.dwellCaption)
                                .foregroundStyle(t.textSecondary)
                        }
                    }
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xxl)
                }
                .scrollIndicators(.hidden)

                PrimaryButton(title: "Continue",
                              enabled: frequency != .custom || !customDays.isEmpty) {
                    onNext(frequency,
                           frequency == .custom ? customDays.sorted() : nil,
                           threshold, moveOnAfter)
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.xl)
        }
        .dwellThemed()
        .animation(.easeOut(duration: 0.2), value: frequency)
    }
}

/// Day-of-week selector for the Custom rhythm. Sends ISO weekdays
/// (1 = Monday … 7 = Sunday), which is what `custom_days` expects.
///
/// DESIGN: invented — the redesign offers "Custom" with no screen behind it.
struct WeekdayPicker: View {
    @Binding var selected: Set<Int>
    @Environment(\.dwell) private var t

    private let days = [(1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")]

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(days, id: \.0) { iso, letter in
                let on = selected.contains(iso)
                Button {
                    Haptics.select()
                    if on { selected.remove(iso) } else { selected.insert(iso) }
                } label: {
                    Text(letter)
                        .font(.dwellSmallMd)
                        .foregroundStyle(on ? t.onInk : t.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(on ? t.ink : t.surface)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(on ? .clear : t.borderStrong, lineWidth: 1))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(["", "Monday", "Tuesday", "Wednesday", "Thursday",
                                     "Friday", "Saturday", "Sunday"][iso])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

#Preview { FrequencyThresholdView() }
