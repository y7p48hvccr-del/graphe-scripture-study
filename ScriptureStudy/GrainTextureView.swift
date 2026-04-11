import SwiftUI

// MARK: - Seeded RNG (deterministic so grain doesn't shift on redraw)

private struct SeededRandom {
    private var seed: UInt64
    init(seed: UInt64 = 12345) { self.seed = seed }
    mutating func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(UInt64(1) << 31)
    }
}

// MARK: - Grain Texture View

struct GrainTextureView: View {

    /// 0 = off, 1 = full
    let intensity: Double
    let themeID:   String

    private var dotColor: Color {
        switch themeID {
        case "sepia":             return Color(red: 0.40, green: 0.28, blue: 0.10)
        case "charcoal", "black": return .white
        default:                  return .black
        }
    }

    // Base opacity — was 0.030 (invisible). Now properly visible.
    private var baseOpacity: Double {
        switch themeID {
        case "black":    return 0.12
        case "charcoal": return 0.14
        case "sepia":    return 0.18
        default:         return 0.16
        }
    }

    var body: some View {
        Canvas { context, size in
            guard intensity > 0 else { return }

            let count = 120_000
            var rng   = SeededRandom(seed: 99991)

            for _ in 0..<count {
                let x     = rng.next() * size.width
                let y     = rng.next() * size.height
                let alpha = (rng.next() * 0.6 + 0.4) * baseOpacity * intensity
                let r     = rng.next() * 1.1 + 0.4   // 0.4–1.5 pt — larger, more visible

                var ctx   = context
                ctx.opacity = alpha
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r/2, y: y - r/2, width: r, height: r)),
                    with: .color(dotColor)
                )
            }

            // Linen weave — was 1.2% opacity (invisible). Now 8%.
            let lineOpacity = 0.08 * intensity
            let spacing: CGFloat = 3

            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(dotColor.opacity(lineOpacity)),
                               lineWidth: 0.5)
                x += spacing
            }

            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(dotColor.opacity(lineOpacity * 0.5)),
                               lineWidth: 0.5)
                y += spacing
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
