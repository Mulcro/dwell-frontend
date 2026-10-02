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
    var action: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button {
            guard enabled, !loading else { return }
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.sm) {
                if loading {
                    ProgressView().tint(t.onInk)
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
        .disabled(!enabled || loading)
    }
}

/// Secondary action — quiet, no fill.
struct SecondaryButton: View {
    let title: String
    var bordered: Bool = false
    var action: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.dwellButton)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
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
