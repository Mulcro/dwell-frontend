import SwiftUI

/// Loading, empty and error treatments in the app's own voice — quiet, not
/// alarmed. Every async surface uses these rather than a bare spinner.

struct LoadingView: View {
    var label: String = "One moment"
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(spacing: Space.md) {
            ProgressView().tint(t.textTertiary)
            Text(label)
                .font(.dwellSmall)
                .foregroundStyle(t.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: () -> Void = {}
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(spacing: Space.md) {
            Text(title)
                .font(.dwellCardTitleStrong)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.dwellBody)
                    .foregroundStyle(t.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(LineSpacing.body)
            }
            if let actionTitle {
                SecondaryButton(title: actionTitle, bordered: true, action: action)
                    .padding(.top, Space.sm)
                    .frame(maxWidth: 260)
            }
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?
    @Environment(\.dwell) private var t

    var body: some View {
        VStack(spacing: Space.md) {
            Text("That didn't load")
                .font(.dwellCardTitleStrong)
                .foregroundStyle(t.textPrimary)
            Text(message)
                .font(.dwellSmall)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(LineSpacing.body)
            if let retry {
                SecondaryButton(title: "Try again", bordered: true, action: retry)
                    .padding(.top, Space.sm)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Renders a Loadable in one line at the call site.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:      LoadingView()
        case .failed(let message): ErrorStateView(message: message, retry: retry)
        case .loaded(let value):   content(value)
        }
    }
}
