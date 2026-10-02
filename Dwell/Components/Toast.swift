import SwiftUI

/// A brief confirmation that something worked.
///
/// Used where an action takes long enough that silence reads as failure —
/// uploading a profile picture, posting a reflection. Deliberately transient
/// and non-blocking: it reports, it doesn't ask.
struct Toast: Equatable, Identifiable {
    enum Kind: Equatable { case success, failure, progress }

    let id = UUID()
    let message: String
    var kind: Kind = .success

    static func success(_ message: String) -> Toast { .init(message: message, kind: .success) }
    static func failure(_ message: String) -> Toast { .init(message: message, kind: .failure) }
    static func working(_ message: String) -> Toast { .init(message: message, kind: .progress) }
}

private struct ToastOverlay: ViewModifier {
    @Binding var toast: Toast?
    @Environment(\.dwell) private var t

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                HStack(spacing: Space.md) {
                    icon(for: toast.kind)
                    Text(toast.message)
                        .font(.dwellSmallMd)
                        .foregroundStyle(t.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .background(t.background)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(t.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .padding(.horizontal, Space.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast.id) {
                    // A progress toast is cleared by whoever set it; the rest
                    // time out on their own.
                    guard toast.kind != .progress else { return }
                    try? await Task.sleep(for: .seconds(2.6))
                    withAnimation { self.toast = nil }
                }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: toast)
    }

    @ViewBuilder
    private func icon(for kind: Toast.Kind) -> some View {
        switch kind {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(t.accent)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(t.danger)
        case .progress:
            ProgressView().scaleEffect(0.8)
        }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastOverlay(toast: toast))
    }
}
