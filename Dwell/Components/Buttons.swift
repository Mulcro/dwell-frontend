import SwiftUI

/// Primary action — near-black pill, white label.
/// Figma: Primary Button component set, SF Pro w590 16, radius 100.
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var loading: Bool = false
    /// Auth screens and the day's main action fill with the cyan accent;
    /// everywhere else the primary action is ink.
    var accent: Bool = false
    /// Optional leading SF Symbol, as on "Send the group a gentle nudge".
    var icon: String? = nil
    /// Shorter pill for in-card actions like Reply, where a full-height
    /// primary button dominates the content it belongs to.
    var compact: Bool = false
    /// A brand mark from the asset catalog, drawn in full colour before the
    /// title, as on "Continue with YouVersion".
    var image: String? = nil
    var action: () -> Void = {}
    /// For work that calls the backend. The button is busy from the moment
    /// of the tap until this returns, so a quick second tap can't send the
    /// request twice. A screen's own flag, set inside its async work, comes
    /// too late: the Task hasn't started when the second tap arrives.
    var perform: (@MainActor () async -> Void)? = nil
    @Environment(\.dwell) private var t
    @State private var busy = false

    var body: some View {
        Button {
            guard enabled, !loading, !busy else { return }
            Haptics.tap()
            if let perform {
                busy = true
                Task {
                    await perform()
                    busy = false
                }
            } else {
                action()
            }
        } label: {
            HStack(spacing: Space.sm) {
                if loading || busy {
                    ProgressView().tint(t.onInk)
                } else if let image {
                    BrandMark(name: image)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                }
                Text(title).font(.dwellButton)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 12 : 18)
            .foregroundStyle(t.onInk)
            .background((accent ? t.accent : t.ink).opacity(enabled ? 1 : 0.35))
            .clipShape(Capsule())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled || loading || busy)
    }
}

/// Secondary action — quiet, no fill.
struct SecondaryButton: View {
    let title: String
    var bordered: Bool = false
    /// Matches PrimaryButton's compact height when the two sit side by side
    /// inside a card.
    var compact: Bool = false
    /// A brand mark drawn before the title, as on "Continue with Google".
    var image: String? = nil
    var action: () -> Void = {}
    /// Async work, busy from the tap until it returns. See PrimaryButton.
    var perform: (@MainActor () async -> Void)? = nil
    @Environment(\.dwell) private var t
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            Haptics.tap()
            if let perform {
                busy = true
                Task {
                    await perform()
                    busy = false
                }
            } else {
                action()
            }
        } label: {
            HStack(spacing: Space.sm) {
                if busy {
                    ProgressView().tint(t.textPrimary)
                } else if let image {
                    BrandMark(name: image)
                }
                Text(title).font(.dwellButton)
            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 12 : 18)
                .foregroundStyle(t.textPrimary)
                .background(bordered ? t.surface : .clear)
                .clipShape(Capsule())
                .overlay {
                    if bordered {
                        Capsule().strokeBorder(t.borderStrong, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PressScale())
        .disabled(busy)
    }
}

/// A plain Button for work that calls the backend: taps are ignored until
/// the last one's work has finished. The label is the caller's, so a
/// screen's own flag still drives any spinner.
struct AsyncButton<Label: View>: View {
    var role: ButtonRole? = nil
    let action: @MainActor () async -> Void
    @ViewBuilder let label: () -> Label
    @State private var busy = false

    var body: some View {
        Button(role: role) {
            guard !busy else { return }
            busy = true
            Task {
                await action()
                busy = false
            }
        } label: {
            label()
        }
        .disabled(busy)
    }
}

/// Every tappable surface in the redesign dips slightly. Cheap, and it makes
/// the whole app feel responsive.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A provider's own logo at button size, in its own colours, never tinted.
/// Brand guidelines want the official marks unaltered on sign-in buttons.
struct BrandMark: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image(name)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}
