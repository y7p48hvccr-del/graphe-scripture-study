import SwiftUI

// MARK: - Filigree Color Presets

struct FiligreeColorPreset: Identifiable {
    let id:    Int
    let name:  String
    let r, g, b: Double
    var color: Color { Color(red: r/255, green: g/255, blue: b/255) }
}

let filigreePresets: [FiligreeColorPreset] = [
    FiligreeColorPreset(id: 0, name: "Pale Blue",     r: 80,  g: 130, b: 185),
    FiligreeColorPreset(id: 1, name: "Pale Sage",     r: 80,  g: 150, b: 90),
    FiligreeColorPreset(id: 2, name: "Pale Gold",     r: 160, g: 125, b: 60),
    FiligreeColorPreset(id: 3, name: "Pale Lavender", r: 120, g: 95,  b: 170),
    FiligreeColorPreset(id: 4, name: "Blush Pink",    r: 190, g: 100, b: 110),
]

// MARK: - Filigree Decoration View

struct FiligreeDecoration: View {

    let colorIndex: Int
    let intensity:  Double   // 0.1 – 1.0

    private var preset: FiligreeColorPreset {
        filigreePresets[min(colorIndex, filigreePresets.count - 1)]
    }

    private func ink(_ alpha: Double) -> Color {
        Color(red: preset.r/255, green: preset.g/255, blue: preset.b/255,
              opacity: max(0, min(1, alpha * intensity * 5.0)))
    }

    var body: some View {
        EmptyView() // Decoration disabled — toggle retained in Settings for future use
    }

    // MARK: - Compose scene

    private func drawAll(context: GraphicsContext, size: CGSize) {
        let W = size.width, H = size.height

        // ── Sidebar region (left ~148 pt) ──
        // Large quill — bottom of sidebar
        drawQuill(context, cx: 95, cy: H - 55, len: 90, rot: -0.52, sc: 1.1, a: 0.95)
        // Ghost quill — upper sidebar
        drawQuill(context, cx: 36, cy: 115, len: 55, rot: -0.63, sc: 0.55, a: 0.38)

        // Corner filigree — top-left
        cornerFiligree(context, x: 4,   y: 4,   fx: false, fy: false, a: 0.80)
        // Corner filigree — bottom-left
        cornerFiligree(context, x: 4,   y: H-4, fx: false, fy: true,  a: 0.60)
        // Corner filigree — top-right of sidebar
        cornerFiligree(context, x: 144, y: 4,   fx: true,  fy: false, a: 0.65)

        // Ornamental rule under sidebar header
        ornamentalRule(context, x: 6, y: 46, w: 132, a: 0.55)

        // Ink splatters near quill nib
        inkSplatter(context, x: 103, y: H - 42, a: 0.70)

        // Tendrils along right edge of sidebar
        for t in [0.25, 0.50, 0.72] {
            tendril(context, x: 142, y: H * t, dx: -11, dy: 9, a: 0.38)
        }

        // ── Tab bar region (top ~42 pt) ──
        // Small quill tucked in right of tab bar
        drawQuill(context, cx: W - 20, cy: 50, len: 46, rot: -0.45, sc: 0.42, a: 0.60)
        // Right corner filigree
        cornerFiligree(context, x: W - 4, y: 4, fx: true, fy: false, a: 0.48)
        // Faint ornamental rule at base of tab bar
        ornamentalRule(context, x: 50, y: 39, w: W - 100, a: 0.30)
    }

    // MARK: - Quill Feather (matches logo style — thin, smooth, no extending barbs)

    private func drawQuill(_ ctx: GraphicsContext,
                           cx: Double, cy: Double, len: Double,
                           rot: Double, sc: Double, a: Double) {
        var c = ctx
        c.transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: rot)
            .scaledBy(x: sc, y: sc)

        let w = len * 0.18   // feather width relative to length

        // Main feather body — thin, asymmetric, dove-wing shaped
        var body = Path()
        body.move(to: CGPoint(x: 0, y: -len))
        body.addQuadCurve(to: CGPoint(x: w, y: -len*0.38),
                          control: CGPoint(x: w*1.1, y: -len*0.72))
        body.addQuadCurve(to: CGPoint(x: w*0.7, y: len*0.22),
                          control: CGPoint(x: w*1.1, y: -len*0.05))
        body.addLine(to: CGPoint(x: w*0.25, y: len*0.12))
        body.addLine(to: CGPoint(x: 0, y: len*0.22))
        body.addLine(to: CGPoint(x: -w*0.25, y: len*0.05))
        body.addQuadCurve(to: CGPoint(x: -w*0.55, y: -len*0.38),
                          control: CGPoint(x: -w*0.6, y: -len*0.05))
        body.closeSubpath()
        c.fill(body, with: .color(ink(a * 0.22)))

        // Soft highlight on leading (right) edge
        var highlight = Path()
        highlight.move(to: CGPoint(x: 0, y: -len))
        highlight.addQuadCurve(to: CGPoint(x: w, y: -len*0.38),
                               control: CGPoint(x: w*1.1, y: -len*0.72))
        highlight.addQuadCurve(to: CGPoint(x: w*0.7, y: len*0.22),
                               control: CGPoint(x: w*1.1, y: -len*0.05))
        highlight.addLine(to: CGPoint(x: w*0.1, y: len*0.18))
        highlight.addLine(to: CGPoint(x: 0, y: -len))
        c.fill(highlight, with: .color(ink(a * 0.08)))

        // Rachis — central shaft, slightly off-centre like a real feather
        var shaft = Path()
        shaft.move(to: CGPoint(x: 0, y: -len))
        shaft.addCurve(to: CGPoint(x: w*0.08, y: len*0.24),
                       control1: CGPoint(x: w*0.05, y: -len*0.4),
                       control2: CGPoint(x: w*0.08, y: len*0.0))
        c.stroke(shaft, with: .color(ink(a * 0.35)), lineWidth: 0.70)

        // Calamus — bare quill below the vane
        var cal = Path()
        cal.move(to: CGPoint(x: w*0.08, y: len*0.24))
        cal.addCurve(to: CGPoint(x: 0, y: len*0.60),
                     control1: CGPoint(x: w*0.06, y: len*0.38),
                     control2: CGPoint(x: 0.5, y: len*0.50))
        c.stroke(cal, with: .color(ink(a * 0.28)), lineWidth: 1.10)

        // Nib — split tip
        var nib = Path()
        nib.move(to: CGPoint(x: 0, y: len*0.60))
        nib.addLine(to: CGPoint(x: -2, y: len*0.72))
        nib.move(to: CGPoint(x: 0, y: len*0.60))
        nib.addLine(to: CGPoint(x:  2, y: len*0.72))
        c.stroke(nib, with: .color(ink(a * 0.22)), lineWidth: 0.70)

        // Ink bead at tip
        var bead = Path()
        bead.addEllipse(in: CGRect(x: -1.5, y: len*0.72, width: 3, height: 3.5))
        c.fill(bead, with: .color(ink(a * 0.18)))
    }

    // MARK: - Corner Filigree

    private func cornerFiligree(_ ctx: GraphicsContext,
                                 x: Double, y: Double,
                                 fx: Bool, fy: Bool, a: Double) {
        var c = ctx
        var t = CGAffineTransform.identity
        if fx { t = t.scaledBy(x: -1, y:  1) }
        if fy { t = t.scaledBy(x:  1, y: -1) }
        t = t.concatenating(CGAffineTransform(translationX: x, y: y))
        c.transform = t

        // Main arc
        var main = Path()
        main.move(to: .zero)
        main.addCurve(to: CGPoint(x: 28, y: 22),
                      control1: CGPoint(x: 20, y:  0),
                      control2: CGPoint(x: 30, y: 10))
        c.stroke(main, with: .color(ink(a * 0.22)), lineWidth: 0.55)

        // Secondary branch upward
        var sec = Path()
        sec.move(to: CGPoint(x: 8, y: 2))
        sec.addCurve(to: CGPoint(x: 30, y: -10),
                     control1: CGPoint(x: 12, y: -8),
                     control2: CGPoint(x: 22, y: -12))
        c.stroke(sec, with: .color(ink(a * 0.18)), lineWidth: 0.45)

        // Tertiary fine branch
        var ter = Path()
        ter.move(to: CGPoint(x: 16, y: 12))
        ter.addCurve(to: CGPoint(x: 38, y: 8),
                     control1: CGPoint(x: 22, y: 6),
                     control2: CGPoint(x: 32, y: 4))
        c.stroke(ter, with: .color(ink(a * 0.13)), lineWidth: 0.35)

        // Spirals at tips
        drawSpiral(c, cx: 28, cy: 22, r2: 5.0, turns: 1.4, a: a*0.65)
        drawSpiral(c, cx: 30, cy: -10, r2: 4.0, turns: 1.2, a: a*0.55)
        drawSpiral(c, cx: 38, cy: 8,  r2: 3.0, turns: 1.0, a: a*0.45)
        drawSpiral(c, cx: 0,  cy: 0,  r2: 3.5, turns: 0.9, a: a*0.40)

        // Tendrils
        tendril(c, x: 28, y: 22, dx:  8, dy: 12, a: a*0.70)
        tendril(c, x: 30, y: -10, dx: 6, dy: -8, a: a*0.60)
        tendril(c, x: 14, y:  6, dx: -4, dy:-10, a: a*0.50)
        tendril(c, x: 20, y: 14, dx: 10, dy:  4, a: a*0.45)

        // Leaf clusters
        leafCluster(c, x: 18, y: 10, a: a*0.70)
        leafCluster(c, x: 24, y: -2, a: a*0.55)
        leafCluster(c, x: 10, y: 18, a: a*0.45)

        // Dots along main branch
        for t in [0.30, 0.55, 0.78] {
            var dot = Path()
            dot.addEllipse(in: CGRect(x: 28*t - 0.9, y: 22*t*t - 0.9, width: 1.8, height: 1.8))
            c.fill(dot, with: .color(ink(a * 0.30)))
        }
    }

    // MARK: - Spiral

    private func spiralPath(cx: Double, cy: Double, r2: Double, turns: Double) -> Path {
        var p = Path()
        let steps = Int(turns * 36)
        for i in 0...steps {
            let t     = Double(i) / Double(steps)
            let angle = t * turns * .pi * 2
            let rad   = r2 * t
            let pt    = CGPoint(x: cx + cos(angle) * rad, y: cy + sin(angle) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    private func drawSpiral(_ ctx: GraphicsContext,
                             cx: Double, cy: Double,
                             r2: Double, turns: Double, a: Double) {
        ctx.stroke(spiralPath(cx: cx, cy: cy, r2: r2, turns: turns),
                   with: .color(ink(a)), lineWidth: 0.42)
    }

    // MARK: - Tendril

    private func tendril(_ ctx: GraphicsContext,
                          x: Double, y: Double,
                          dx: Double, dy: Double, a: Double) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        p.addCurve(to: CGPoint(x: x+dx, y: y+dy),
                   control1: CGPoint(x: x+dx*0.3, y: y+dy*0.1),
                   control2: CGPoint(x: x+dx*0.6, y: y+dy*0.5))
        ctx.stroke(p, with: .color(ink(a)), lineWidth: 0.38)
        drawSpiral(ctx, cx: x+dx, cy: y+dy, r2: 3.5, turns: 1.2, a: a*0.70)
    }

    // MARK: - Leaf Cluster

    private func leafCluster(_ ctx: GraphicsContext, x: Double, y: Double, a: Double) {
        for ang in [-0.6, -0.2, 0.2, 0.6, 1.0] {
            let lx = x + cos(ang) * 9
            let ly = y + sin(ang) * 9
            var leaf = Path()
            leaf.move(to: CGPoint(x: x, y: y))
            leaf.addQuadCurve(to: CGPoint(x: lx, y: ly),
                              control: CGPoint(x: x + cos(ang-0.5)*7, y: y + sin(ang-0.5)*7))
            leaf.addQuadCurve(to: CGPoint(x: x, y: y),
                              control: CGPoint(x: x + cos(ang+0.5)*7, y: y + sin(ang+0.5)*7))
            ctx.fill(leaf,   with: .color(ink(a * 0.12)))
            ctx.stroke(leaf, with: .color(ink(a * 0.18)), lineWidth: 0.28)
        }
    }

    // MARK: - Ornamental Rule

    private func ornamentalRule(_ ctx: GraphicsContext,
                                 x: Double, y: Double, w: Double, a: Double) {
        var line = Path()
        line.move(to: CGPoint(x: x, y: y)); line.addLine(to: CGPoint(x: x+w, y: y))
        ctx.stroke(line, with: .color(ink(a * 0.14)), lineWidth: 0.38)

        // Diamonds
        for t in [0.25, 0.50, 0.75] {
            let lx = x + t * w
            var d  = Path()
            d.move(to:     CGPoint(x: lx,     y: y-2.5))
            d.addLine(to:  CGPoint(x: lx+2.5, y: y))
            d.addLine(to:  CGPoint(x: lx,     y: y+2.5))
            d.addLine(to:  CGPoint(x: lx-2.5, y: y))
            d.closeSubpath()
            ctx.fill(d, with: .color(ink(a * 0.22)))
        }

        drawSpiral(ctx, cx: x,   cy: y, r2: 5, turns: 1.2, a: a*0.55)
        drawSpiral(ctx, cx: x+w, cy: y, r2: 5, turns: 1.2, a: a*0.55)
    }

    // MARK: - Ink Splatter

    private func inkSplatter(_ ctx: GraphicsContext, x: Double, y: Double, a: Double) {
        var main = Path()
        main.addEllipse(in: CGRect(x: x-2, y: y-2, width: 4, height: 4))
        ctx.fill(main, with: .color(ink(a * 0.35)))

        for (dx, dy, r) in [(3.5,-2.0,0.8),(-4.0,2.5,0.65),(5.0,3.5,0.5),(-2.0,-3.5,0.7),(1.0,5.0,0.55)] {
            var dot = Path()
            dot.addEllipse(in: CGRect(x: x+dx-r, y: y+dy-r, width: r*2, height: r*2))
            ctx.fill(dot, with: .color(ink(a * 0.18)))
        }
    }
}

// MARK: - Global accent colour helper
// Returns the filigree colour at full saturation for use in UI elements
// (verse numbers, bookmarks, note icons etc.)

extension FiligreeColorPreset {
    /// Saturated version for light backgrounds — darkened so it reads against white/cream
    var filigreeAccent: Color {
        Color(red:   (r / 255) * 0.62,
              green: (g / 255) * 0.60,
              blue:  (b / 255) * 0.58)
    }

    /// Luminous version for dark backgrounds — brightened so it glows against charcoal/black
    var filigreeAccentBright: Color {
        Color(red:   min(0.88, (r / 255) * 1.65),
              green: min(0.88, (g / 255) * 1.60),
              blue:  min(0.88, (b / 255) * 1.55))
    }

    /// Pastel version for solid fills — keeps the hue readable without going dark and muddy
    var filigreeAccentFill: Color {
        // Blend toward white so the colour stays recognisable at full opacity
        let rr = (r / 255) * 0.55 + 0.42
        let gg = (g / 255) * 0.55 + 0.42
        let bb = (b / 255) * 0.55 + 0.42
        return Color(red: min(1, rr), green: min(1, gg), blue: min(1, bb))
    }

    /// Pastel fill for dark themes
    var filigreeAccentFillBright: Color {
        let rr = min(0.95, (r / 255) * 0.85 + 0.12)
        let gg = min(0.95, (g / 255) * 0.85 + 0.12)
        let bb = min(0.95, (b / 255) * 0.85 + 0.12)
        return Color(red: rr, green: gg, blue: bb)
    }
}

/// Returns the correct filigree accent for the current theme —
/// luminous on dark backgrounds, saturated on light ones.
func resolvedFiligreeAccent(colorIndex: Int, themeID: String) -> Color {
    let preset = filigreePresets[min(colorIndex, filigreePresets.count - 1)]
    return themeID == "charcoal"
        ? preset.filigreeAccentBright
        : preset.filigreeAccent
}

func resolvedFiligreeAccentFill(colorIndex: Int, themeID: String) -> Color {
    let preset = filigreePresets[min(colorIndex, filigreePresets.count - 1)]
    return themeID == "charcoal"
        ? preset.filigreeAccentFillBright
        : preset.filigreeAccentFill
}
