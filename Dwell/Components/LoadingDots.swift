import SwiftUI

/// Three dots that bob in turn while something is on its way. Still under
/// Reduce Motion.
struct LoadingDots: View {
    var color: Color
    var dotSize: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: reduceMotion ? 0 : (up ? -dotSize / 2 : dotSize / 2))
                    .animation(.easeInOut(duration: 0.4)
                                   .repeatForever(autoreverses: true)
                                   .delay(Double(i) * 0.15),
                               value: up)
            }
        }
        .onAppear { up = true }
        .accessibilityLabel("Sending")
    }
}

#Preview {
    LoadingDots(color: .cyan).padding()
}
