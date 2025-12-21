import SwiftUI

// MARK: - CassetteIcon

/// A custom cassette tape icon view.
@available(macOS 26.0, *)
struct CassetteIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Cassette body (rounded rectangle)
            RoundedRectangle(cornerRadius: size * 0.12)
                .frame(width: size, height: size * 0.65)

            // Inner window (darker area showing tape reels)
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(.background.opacity(0.3))
                .frame(width: size * 0.85, height: size * 0.35)
                .offset(y: -size * 0.05)

            // Left tape reel
            Circle()
                .fill(.background.opacity(0.5))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.22, y: -size * 0.05)

            Circle()
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: -size * 0.22, y: -size * 0.05)

            // Right tape reel
            Circle()
                .fill(.background.opacity(0.5))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.22, y: -size * 0.05)

            Circle()
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.22, y: -size * 0.05)

            // Bottom label area
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(.background.opacity(0.2))
                .frame(width: size * 0.5, height: size * 0.1)
                .offset(y: size * 0.2)
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    CassetteIcon(size: 80)
        .foregroundStyle(.pink)
}
