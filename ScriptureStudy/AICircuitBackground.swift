import SwiftUI

struct AICircuitBackground: View {

    let themeID: String

    private var lineColor: Color {
        switch themeID {
        case "sepia":             return Color(red: 0.45, green: 0.32, blue: 0.12)
        case "charcoal", "black": return Color(red: 0.4,  green: 0.8,  blue: 0.6)
        default:                  return Color(red: 0.2,  green: 0.4,  blue: 0.7)
        }
    }

    private var nodeColor: Color {
        switch themeID {
        case "sepia":             return Color(red: 0.55, green: 0.38, blue: 0.15)
        case "charcoal", "black": return Color(red: 0.3,  green: 0.9,  blue: 0.6)
        default:                  return Color(red: 0.15, green: 0.45, blue: 0.75)
        }
    }

    private var lineOpacity: Double {
        switch themeID {
        case "charcoal", "black": return 0.18
        default:                  return 0.10
        }
    }

    var body: some View {
        Canvas { ctx, size in
            drawCircuit(ctx: ctx, size: size)
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }

    private func drawCircuit(ctx: GraphicsContext, size: CGSize) {
        var rng = SeededRNG(seed: 42)
        let W   = size.width
        let H   = size.height

        // ── Grid dots ──
        let gridSpacing: CGFloat = 36
        var gx: CGFloat = gridSpacing
        while gx < W {
            var gy: CGFloat = gridSpacing
            while gy < H {
                let dotPath = Path(ellipseIn: CGRect(x: gx-1, y: gy-1, width: 2, height: 2))
                ctx.fill(dotPath, with: .color(lineColor.opacity(lineOpacity * 0.6)))
                gy += gridSpacing
            }
            gx += gridSpacing
        }

        // ── Circuit traces — horizontal then vertical segments with right-angle bends ──
        let traceCount = 28
        for _ in 0..<traceCount {
            let startX  = CGFloat(rng.next()) * W
            let startY  = snap(CGFloat(rng.next()) * H, to: gridSpacing)
            let segs    = Int(rng.next() * 4) + 2
            var x       = snap(startX, to: gridSpacing)
            var y       = startY
            var path    = Path()
            path.move(to: CGPoint(x: x, y: y))
            var horizontal = rng.next() > 0.5

            for _ in 0..<segs {
                let length = (CGFloat(Int(rng.next() * 4) + 1)) * gridSpacing
                if horizontal {
                    x += rng.next() > 0.5 ? length : -length
                    x  = max(gridSpacing, min(W - gridSpacing, x))
                } else {
                    y += rng.next() > 0.5 ? length : -length
                    y  = max(gridSpacing, min(H - gridSpacing, y))
                }
                path.addLine(to: CGPoint(x: x, y: y))
                horizontal = !horizontal
            }

            ctx.stroke(path, with: .color(lineColor.opacity(lineOpacity)),
                       style: StrokeStyle(lineWidth: 0.8, lineCap: .square))
        }

        // ── Nodes — squares at trace intersections / endpoints ──
        let nodeCount = 40
        for _ in 0..<nodeCount {
            let nx   = snap(CGFloat(rng.next()) * W, to: gridSpacing)
            let ny   = snap(CGFloat(rng.next()) * H, to: gridSpacing)
            let size = rng.next() > 0.7 ? CGFloat(5) : CGFloat(3)
            let rect = CGRect(x: nx - size/2, y: ny - size/2, width: size, height: size)
            ctx.fill(Path(rect), with: .color(nodeColor.opacity(lineOpacity * 1.4)))
            // Outer ring on larger nodes
            if size == 5 {
                let ring = CGRect(x: nx-5, y: ny-5, width: 10, height: 10)
                ctx.stroke(Path(ellipseIn: ring),
                           with: .color(nodeColor.opacity(lineOpacity * 0.8)),
                           lineWidth: 0.6)
            }
        }

        // ── IC chip outlines ──
        let chipCount = 4
        for _ in 0..<chipCount {
            let cx   = snap(CGFloat(rng.next()) * (W - 120) + 60, to: gridSpacing)
            let cy   = snap(CGFloat(rng.next()) * (H - 80)  + 40, to: gridSpacing)
            let cw   = CGFloat((Int(rng.next() * 2) + 2)) * gridSpacing * 2
            let ch   = gridSpacing * 2
            let rect = CGRect(x: cx - cw/2, y: cy - ch/2, width: cw, height: ch)
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                       with: .color(nodeColor.opacity(lineOpacity * 1.2)),
                       lineWidth: 0.8)
            // Pin lines on chip edges
            let pins = Int(cw / gridSpacing)
            for p in 0..<pins {
                let px = rect.minX + CGFloat(p) * gridSpacing + gridSpacing/2
                // Top pin
                var pin = Path()
                pin.move(to: CGPoint(x: px, y: rect.minY))
                pin.addLine(to: CGPoint(x: px, y: rect.minY - 8))
                ctx.stroke(pin, with: .color(lineColor.opacity(lineOpacity)),
                           lineWidth: 0.7)
                // Bottom pin
                var pin2 = Path()
                pin2.move(to: CGPoint(x: px, y: rect.maxY))
                pin2.addLine(to: CGPoint(x: px, y: rect.maxY + 8))
                ctx.stroke(pin2, with: .color(lineColor.opacity(lineOpacity)),
                           lineWidth: 0.7)
            }
        }
    }

    private func snap(_ value: CGFloat, to grid: CGFloat) -> CGFloat {
        (value / grid).rounded() * grid
    }
}

// MARK: - Seeded RNG (deterministic — same pattern every render)

private struct SeededRNG {
    private var seed: UInt64
    init(seed: UInt64) { self.seed = seed }
    mutating func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(UInt64(1) << 31)
    }
}
