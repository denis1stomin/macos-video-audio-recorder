import SwiftUI

/// A single fixed width shared by all three app windows (configure, select source, processing),
/// so the window doesn't visibly jump side-to-side as the app moves between them. Height is left
/// for each window to size to its own content — forcing all three to the same height left the
/// shorter windows surrounded by large, empty padding.
enum RexGrabWindowSize {
    static let width: CGFloat = 560
}

/// Shared "green dino" accent palette, matching the app icon.
enum DinoPalette {
    static let light = Color(red: 0.443, green: 0.690, blue: 0.463)
    static let mid = Color(red: 0.337, green: 0.569, blue: 0.373)
    static let dark = Color(red: 0.208, green: 0.404, blue: 0.267)
}

/// A soft green gradient wash with blurred dino-skin spots, sitting behind window content.
/// Sized via GeometryReader so it always matches whatever size its host view resolves to —
/// it never forces a size of its own, so it can't cause the host window to clip or overflow.
private struct DinoBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private let spots: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.04, 0.02, 0.34, 0.22),
        (0.94, 0.06, 0.3, 0.2),
        (0.0, 0.88, 0.26, 0.26),
        (0.97, 0.92, 0.28, 0.24),
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [DinoPalette.light.opacity(topOpacity), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ForEach(spots.indices, id: \.self) { index in
                    let spot = spots[index]
                    Ellipse()
                        .fill(DinoPalette.mid.opacity(spotOpacity))
                        .frame(width: size.width * spot.w, height: size.height * spot.h)
                        .position(x: size.width * spot.x, y: size.height * spot.y)
                        .blur(radius: 20)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var topOpacity: Double { colorScheme == .dark ? 0.16 : 0.26 }
    private var spotOpacity: Double { colorScheme == .dark ? 0.1 : 0.15 }
}

extension View {
    /// Applies the shared dino-themed window background (soft green wash + spots).
    func dinoThemedBackground() -> some View {
        background(DinoBackdrop())
    }
}

/// The circular camera badge echoing the app icon, for use as a small in-window brand mark.
struct DinoBadge: View {
    var diameter: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(DinoPalette.mid, lineWidth: 2)
            Image(systemName: "video.fill")
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(DinoPalette.mid)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}
