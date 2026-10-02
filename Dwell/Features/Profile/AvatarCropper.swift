import SwiftUI

/// Pan and pinch to choose what the circle shows, then confirm.
///
/// The preview and the exported image are rendered from the *same* view, so
/// what you framed is exactly what uploads — building the crop rect by hand
/// and hoping it matches the preview is where this usually goes wrong.
struct AvatarCropper: View {
    let image: UIImage
    var onCancel: () -> Void = {}
    var onUse: (UIImage) -> Void = { _ in }

    @Environment(\.dwell) private var t
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - Space.gutter * 2, geo.size.height * 0.6)

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: Space.xxl) {
                    Spacer()

                    ZStack {
                        cropped(side: side)
                        Circle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: side, height: side)
                            .allowsHitTesting(false)
                    }
                    .frame(width: side, height: side)
                    .gesture(dragging(side: side))
                    .simultaneousGesture(zooming(side: side))

                    Text("Drag to move · pinch to zoom")
                        .font(.dwellSmall)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    HStack(spacing: Space.md) {
                        Button("Cancel", action: onCancel)
                            .font(.dwellButton)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))

                        Button("Use photo") { onUse(render(side: side)) }
                            .font(.dwellButton)
                            .foregroundStyle(t.onInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(t.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xl)
                }
            }
        }
    }

    /// The single source of truth for framing — displayed, and rendered.
    private func cropped(side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: side, height: side)
            .clipShape(Circle())
    }

    private func dragging(side: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height)
            }
            .onEnded { _ in settle(side: side) }
    }

    private func zooming(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, minScale), maxScale)
            }
            .onEnded { _ in
                committedScale = scale
                // Zooming back out can leave an offset that was legal at the
                // larger scale but now exposes an edge.
                settle(side: side)
            }
    }

    /// Springs the photo back so it always covers the circle — otherwise you
    /// can drag past the edge and crop in a wedge of blank background.
    private func settle(side: CGFloat) {
        let limit = maxOffset(side: side)
        let clamped = CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height))
        if clamped != offset {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = clamped }
        }
        committedOffset = clamped
    }

    /// How far the photo can travel before an edge enters the frame.
    private func maxOffset(side: CGFloat) -> CGSize {
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        // `scaledToFill` matches the short side to the frame and overflows the
        // long one, so only one dimension starts with slack.
        let filled = aspect >= 1
            ? CGSize(width: side * aspect, height: side)
            : CGSize(width: side, height: side / aspect)
        return CGSize(width: max(0, (filled.width * scale - side) / 2),
                      height: max(0, (filled.height * scale - side) / 2))
    }

    @MainActor
    private func render(side: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: cropped(side: side))
        // 3x gives a 1024px-ish square from a 340pt frame — ample for an
        // avatar, and still well inside the 5 MB limit after JPEG.
        renderer.scale = 3
        return renderer.uiImage ?? image
    }
}
