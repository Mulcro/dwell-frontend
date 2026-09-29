import SwiftUI

/// Labelled text field with helper and error slots.
/// Figma: Build New Group / Sign Up — "Label / Description / placeholder / Error".
struct DwellField: View {
    let label: String
    var placeholder: String = ""
    var description: String? = nil
    var error: String? = nil
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    @Binding var text: String
    @Environment(\.dwell) private var t
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label)
                .font(.dwellSmallMd)
                .foregroundStyle(t.textPrimary)

            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.dwellBody)
            .foregroundStyle(t.textPrimary)
            .textFieldStyle(.plain)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .focused($focused)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 16)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            if let error {
                Text(error).font(.dwellCaption).foregroundStyle(t.danger)
            } else if let description {
                Text(description).font(.dwellCaption).foregroundStyle(t.textSecondary)
            }
        }
        .animation(.easeOut(duration: 0.15), value: focused)
        .animation(.easeOut(duration: 0.15), value: error)
    }

    private var borderColor: Color {
        if error != nil { return t.danger }
        return focused ? t.ink : t.borderStrong
    }
}

/// Six-box invite code entry backed by one hidden field.
/// Figma: Join Code Input component set.
struct CodeInput: View {
    @Binding var code: String
    var length: Int = 6
    @FocusState private var focused: Bool
    @Environment(\.dwell) private var t

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .opacity(0.01)
                .onChange(of: code) { _, new in
                    let cleaned = new.uppercased().filter { $0.isLetter || $0.isNumber }
                    code = String(cleaned.prefix(length))
                }

            HStack(spacing: Space.sm) {
                ForEach(0..<length, id: \.self) { index in
                    let characters = Array(code)
                    let value = index < characters.count ? String(characters[index]) : nil
                    let isNext = index == characters.count && focused

                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(t.surface)
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(isNext ? t.ink : t.borderStrong, lineWidth: 1)
                        Text(value ?? "–")
                            .font(.dwellCode)
                            .foregroundStyle(value == nil ? t.textTertiary : t.textPrimary)
                    }
                    .frame(height: 56)
                    .animation(.easeOut(duration: 0.12), value: isNext)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
    }
}

/// Segmented pill row — Frequency (Daily / 4 Days/Week / Custom) and anywhere
/// else the redesign offers a small set of choices.
struct SegmentedChips<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item
    @Environment(\.dwell) private var t

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(items) { item in
                let selected = item == selection
                Button {
                    Haptics.select()
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.dwellSmallMd)
                        .foregroundStyle(selected ? t.onInk : t.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? t.ink : t.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(selected ? .clear : t.borderStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(PressScale())
            }
        }
    }
}

/// Stepper used for the unlock threshold — big value, − / + either side.
struct ThresholdStepper: View {
    @Binding var percent: Int
    var step: Int = 10
    var range: ClosedRange<Int> = 10...100
    @Environment(\.dwell) private var t

    var body: some View {
        HStack {
            stepButton("minus", enabled: percent > range.lowerBound) {
                percent = max(range.lowerBound, percent - step)
            }
            Spacer()
            Text("\(percent)%")
                .font(.dwellTitle)
                .foregroundStyle(t.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: percent)
            Spacer()
            stepButton("plus", enabled: percent < range.upperBound) {
                percent = min(range.upperBound, percent + step)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? t.textPrimary : t.textTertiary)
                .frame(width: 40, height: 40)
                .background(t.surfaceRaised)
                .clipShape(Circle())
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
    }
}
