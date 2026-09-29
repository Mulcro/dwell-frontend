import SwiftUI

/// Left-edge drag to go back.
///
/// The app draws its own nav bars rather than using SwiftUI's, which means
/// there's no system pop gesture to inherit. Rather than reaching into
/// UINavigationController, this is a self-contained edge gesture that calls
/// the same closure the back button does.
struct EdgeSwipeBack: ViewModifier {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private let edgeWidth: CGFloat = 28
    private let commitDistance: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { value in
                        guard value.startLocation.x <= edgeWidth else { return }
                        guard value.translation.width > 0 else { return }
                        offset = reduceMotion ? 0 : value.translation.width * 0.6
                    }
                    .onEnded { value in
                        defer { withAnimation(.easeOut(duration: 0.2)) { offset = 0 } }
                        guard value.startLocation.x <= edgeWidth,
                              value.translation.width > commitDistance else { return }
                        Haptics.tap()
                        action()
                    }
            )
    }
}

extension View {
    /// Adds left-edge swipe-to-go-back that runs the same closure as the
    /// screen's back or close button.
    func edgeSwipeBack(perform action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBack(action: action))
    }
}
