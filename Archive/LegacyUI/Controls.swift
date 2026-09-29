import SwiftUI

enum DwellButtonStyleKind { case primary, secondary, quiet }

struct DwellButton: View {
    let title: String
    var kind: DwellButtonStyleKind = .primary
    var action: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dwellButton)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .foregroundStyle(foreground)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return t.onAccent
        case .secondary, .quiet: return t.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return t.accent
        case .secondary: return t.surface
        case .quiet: return .clear
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .secondary, .quiet: return t.border
        }
    }
}

/// Rounded surface panel — the workhorse container in this design.
struct Panel<Content: View>: View {
    var padding: CGFloat = Space.lg
    var radius: CGFloat = Radius.lg
    var accented: Bool = false
    var dashed: Bool = false
    @ViewBuilder var content: Content
    @Environment(\.dwell) private var t

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        accented ? t.accent.opacity(0.45) : t.border,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 4] : [])
                    )
            )
    }
}

/// Selectable pill — "Voice / Text / Photo", "Mine / Group / Voice".
struct PillToggle: View {
    let title: String
    let selected: Bool
    var trailingChevron: Bool = false
    var action: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title).font(.dwellFootnoteMd)
                if trailingChevron {
                    Text("▾").font(.system(size: 8))
                }
            }
            .foregroundStyle(selected ? t.onAccent : t.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(selected ? t.accent : .clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(selected ? .clear : t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Top bar: leading glyph, centred title, optional trailing glyph.
struct DwellNavBar: View {
    var leading: String? = "←"
    var title: String? = nil
    var trailing: String? = nil
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.dwellFootnoteMd)
                    .foregroundStyle(t.textPrimary)
            }
            HStack {
                if let leading {
                    Button(action: onLeading) {
                        Text(leading)
                            .font(.system(size: 21, weight: .light))
                            .foregroundStyle(t.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let trailing {
                    Button(action: onTrailing) {
                        Text(trailing)
                            .font(.dwellBodyMd)
                            .foregroundStyle(t.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 44)
    }
}

/// Small diamond mark that stands for the Companion throughout the design.
struct CompanionMark: View {
    var size: CGFloat = 26
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            Circle().fill(t.accentWash)
            Text("◈")
                .font(.system(size: size * 0.44))
                .foregroundStyle(t.accent)
        }
        .frame(width: size, height: size)
    }
}
