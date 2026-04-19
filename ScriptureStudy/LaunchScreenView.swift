import SwiftUI

struct LaunchScreenView: View {
    @AppStorage("showLaunchAnimation") var showAnimation: Bool = true
    var onComplete: () -> Void

    @State private var scale:   CGFloat = 0.3
    @State private var opacity: Double  = 0.0
    @State private var fadeScale: CGFloat = 1.0

    private let skyBlue = Color(red: 0.788, green: 0.843, blue: 0.894)

    var body: some View {
        ZStack {
            skyBlue.ignoresSafeArea()
            Image("GrapheOneLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 320, height: 320)
                .scaleEffect(scale * fadeScale)
                .opacity(opacity)
        }
        .onAppear {
            guard showAnimation else { onComplete(); return }
            runAnimation()
        }
    }

    private func runAnimation() {
        withAnimation(.easeOut(duration: 1.8)) {
            scale   = 1.0
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 1.8)) {
                opacity   = 0.0
                fadeScale = 1.5
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { onComplete() }
        }
    }
}

// MARK: - Logo View

struct LogoView: View {
    private let skyBlue = Color(red: 0.788, green: 0.843, blue: 0.894)
    private let gold    = Color(red: 0.784, green: 0.663, blue: 0.431)

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let r  = min(cx, cy) - 2
            let bg = Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2))
            ctx.fill(bg, with: .color(skyBlue))
            ctx.stroke(bg, with: .color(gold.opacity(0.35)), lineWidth: r * 0.018)
            let s = r / 76.0
            let vr = CGRect(x: cx - 4.5*s, y: cy - 50*s, width: 9*s, height: 110*s)
            ctx.fill(Path(roundedRect: vr, cornerRadius: 2*s), with: .color(gold.opacity(0.82)))
            let hr = CGRect(x: cx - 30*s, y: cy - 18*s, width: 60*s, height: 9*s)
            ctx.fill(Path(roundedRect: hr, cornerRadius: 2*s), with: .color(gold.opacity(0.82)))
            ctx.withCGContext { cg in
                cg.translateBy(x: cx + 6*s, y: cy + 6*s)
                cg.rotate(by: .pi / 4)
                #if os(macOS)
                let cream     = NSColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 1)
                let white     = NSColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
                let barbLeft  = NSColor(red: 0.72, green: 0.68, blue: 0.52, alpha: 0.88)
                let barbRight = NSColor(red: 0.84, green: 0.81, blue: 0.70, alpha: 0.82)
                let rachis    = NSColor(red: 0.72, green: 0.58, blue: 0.35, alpha: 1)
                let calamus   = NSColor(red: 0.77, green: 0.64, blue: 0.40, alpha: 1)
                let nibDark   = NSColor(red: 0.35, green: 0.22, blue: 0.08, alpha: 1)
                #else
                let cream     = UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 1)
                let white     = UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
                let barbLeft  = UIColor(red: 0.72, green: 0.68, blue: 0.52, alpha: 0.88)
                let barbRight = UIColor(red: 0.84, green: 0.81, blue: 0.70, alpha: 0.82)
                let rachis    = UIColor(red: 0.72, green: 0.58, blue: 0.35, alpha: 1)
                let calamus   = UIColor(red: 0.77, green: 0.64, blue: 0.40, alpha: 1)
                let nibDark   = UIColor(red: 0.35, green: 0.22, blue: 0.08, alpha: 1)
                #endif
                let leftVane = CGMutablePath()
                leftVane.move(to: CGPoint(x: 0, y: -30*s))
                leftVane.addCurve(to: CGPoint(x: -5*s, y: -12*s), control1: CGPoint(x: -1*s, y: -26*s), control2: CGPoint(x: -6*s, y: -20*s))
                leftVane.addCurve(to: CGPoint(x: -6*s, y: 8*s),   control1: CGPoint(x: -6*s, y: -6*s),  control2: CGPoint(x: -6.5*s, y: 2*s))
                leftVane.addCurve(to: CGPoint(x: -3*s, y: 22*s),  control1: CGPoint(x: -5.5*s, y: 14*s), control2: CGPoint(x: -4*s, y: 18*s))
                leftVane.addLine(to: CGPoint(x: 0, y: 26*s))
                leftVane.closeSubpath()
                cg.addPath(leftVane); cg.setFillColor(cream.cgColor); cg.fillPath()
                let rightVane = CGMutablePath()
                rightVane.move(to: CGPoint(x: 0, y: -30*s))
                rightVane.addCurve(to: CGPoint(x: 3.5*s, y: -12*s), control1: CGPoint(x: 1*s, y: -26*s),  control2: CGPoint(x: 4*s, y: -20*s))
                rightVane.addCurve(to: CGPoint(x: 4*s,   y: 8*s),   control1: CGPoint(x: 4*s, y: -6*s),   control2: CGPoint(x: 4.5*s, y: 2*s))
                rightVane.addCurve(to: CGPoint(x: 2*s,   y: 22*s),  control1: CGPoint(x: 3.5*s, y: 14*s), control2: CGPoint(x: 2.5*s, y: 18*s))
                rightVane.addLine(to: CGPoint(x: 0, y: 26*s))
                rightVane.closeSubpath()
                cg.addPath(rightVane); cg.setFillColor(white.cgColor); cg.fillPath()
                cg.setLineWidth(0.38 * s)
                cg.setStrokeColor(barbLeft.cgColor)
                let lb: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                    (-0.3,-28.5,-4.5,-25),(-0.3,-26,-5,-22),(-0.3,-23.5,-5.5,-19.5),
                    (-0.3,-21,-6,-17),(-0.3,-18.5,-6.5,-14.5),(-0.3,-16,-6.5,-12),
                    (-0.3,-13.5,-6.5,-9.5),(-0.3,-11,-6.5,-7),(-0.3,-8.5,-6.5,-4.5),
                    (-0.3,-6,-6.5,-2),(-0.3,-3.5,-6.5,0.5),(-0.3,-1,-6,3),
                    (-0.3,1.5,-6,5.5),(-0.3,4,-5.5,8),(-0.3,6.5,-5,10.5),
                    (-0.3,9,-4.5,13),(-0.3,11.5,-4,15),(-0.3,14,-3.5,17.5),
                    (-0.3,16.5,-3,20),(-0.3,19,-1.5,22),(-0.3,21.5,-0.5,24),
                ]
                for (x1,y1,x2,y2) in lb { cg.move(to: CGPoint(x: x1*s, y: y1*s)); cg.addLine(to: CGPoint(x: x2*s, y: y2*s)) }
                cg.strokePath()
                cg.setStrokeColor(barbRight.cgColor)
                let rb: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                    (0.3,-28.5,3,-25),(0.3,-26,3.5,-22),(0.3,-23.5,4,-19.5),
                    (0.3,-21,4,-17),(0.3,-18.5,4.5,-14.5),(0.3,-16,4.5,-12),
                    (0.3,-13.5,4.5,-9.5),(0.3,-11,4.5,-7),(0.3,-8.5,4.5,-4.5),
                    (0.3,-6,4.5,-2),(0.3,-3.5,4.5,0.5),(0.3,-1,4,3),
                    (0.3,1.5,4,5.5),(0.3,4,3.5,8),(0.3,6.5,3,10.5),
                    (0.3,9,3,13),(0.3,11.5,2.5,15),(0.3,14,2,17.5),
                    (0.3,16.5,1.5,20),(0.3,19,1,22),(0.3,21.5,0.5,24),
                ]
                for (x1,y1,x2,y2) in rb { cg.move(to: CGPoint(x: x1*s, y: y1*s)); cg.addLine(to: CGPoint(x: x2*s, y: y2*s)) }
                cg.strokePath()
                cg.setStrokeColor(rachis.cgColor); cg.setLineWidth(0.7 * s)
                cg.move(to: CGPoint(x: 0.2*s, y: -30*s))
                cg.addCurve(to: CGPoint(x: 0.4*s, y: 26*s), control1: CGPoint(x: 0.5*s, y: -5*s), control2: CGPoint(x: 0.4*s, y: 12*s))
                cg.strokePath()
                cg.setStrokeColor(calamus.cgColor); cg.setLineWidth(1.3 * s)
                cg.move(to: CGPoint(x: 0.4*s, y: 26*s)); cg.addLine(to: CGPoint(x: 0.6*s, y: 40*s))
                cg.strokePath()
                cg.setStrokeColor(nibDark.cgColor); cg.setLineWidth(0.85 * s)
                cg.move(to: CGPoint(x: -1.2*s, y: 37*s)); cg.addLine(to: CGPoint(x: 0.5*s, y: 43*s))
                cg.move(to: CGPoint(x:  2.2*s, y: 37*s)); cg.addLine(to: CGPoint(x: 0.5*s, y: 43*s))
                cg.move(to: CGPoint(x:  0.5*s, y: 40*s)); cg.addLine(to: CGPoint(x: 0.6*s, y: 46*s))
                cg.strokePath()
            }
        }
    }
}
