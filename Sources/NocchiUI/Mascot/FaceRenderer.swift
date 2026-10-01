import SwiftUI

/// Draws one face into a Canvas. The canvas is larger than the face (see `FaceView.canvasScale`)
/// so accessories like the ring, badge and sparkles have room.
enum FaceRenderer {
    static func draw(
        _ context: GraphicsContext,
        canvas: CGSize,
        size s: CGFloat,
        params p: FaceParams,
        color base: RGBA,
        gaze: CGVector,
        t: Double
    ) {
        var g = context
        let r = s / 2
        g.translateBy(x: canvas.width / 2 + p.offset.dx * s, y: canvas.height / 2 + p.offset.dy * s)
        g.rotate(by: .radians(p.rotation))
        g.scaleBy(x: p.scale, y: p.scale)

        // Amber "needs you" ring.
        if p.ring > 0.01 {
            let rr = r + 0.09 * s
            g.stroke(Circle().path(in: CGRect(x: -rr, y: -rr, width: 2 * rr, height: 2 * rr)),
                     with: .color(FacePalette.ring.opacity(p.ring).color), lineWidth: 0.06 * s)
        }

        // Body: soft radial shading, tinted for error and sleep.
        let body = base.mixed(with: FacePalette.error, p.redness).darker(p.dim)
        let bodyRect = CGRect(x: -r, y: -r, width: s, height: s)
        g.fill(Circle().path(in: bodyRect), with: .radialGradient(
            Gradient(colors: [body.lighter(0.35).color, body.color, body.darker(0.18).color]),
            center: CGPoint(x: -0.3 * r, y: -0.35 * r), startRadius: 0, endRadius: 1.5 * r
        ))

        drawEyes(g, s: s, p: p, gaze: gaze)

        if p.errorDot > 0.01 {
            // Outlined so it stays visible on the red-tinted body.
            let d = 0.2 * s
            let dot = CGRect(x: -0.62 * r - d / 2, y: -0.62 * r - d / 2, width: d, height: d)
            g.fill(Circle().path(in: dot.insetBy(dx: -0.03 * s, dy: -0.03 * s)),
                   with: .color(RGBA.black.opacity(p.errorDot * 0.85).color))
            g.fill(Circle().path(in: dot), with: .color(FacePalette.error.lighter(0.15).opacity(p.errorDot).color))
        }
        if p.badge > 0.01 { drawBadge(g, r: r, opacity: p.badge, t: t) }
        if p.sparkles > 0.01 { drawSparkles(g, r: r, opacity: p.sparkles, t: t) }
        if p.zzz > 0.01 { drawZzz(g, r: r, opacity: p.zzz, t: t) }
    }

    private static func drawEyes(_ g: GraphicsContext, s: CGFloat, p: FaceParams, gaze: CGVector) {
        let travel = 0.07 * s
        let y = p.eyeY * s + gaze.dy * travel
        let w = p.eyeWidth * s
        let h = max(p.eyeHeight * s, 0.02 * s)

        for side in [-1.0, 1.0] {
            let x = side * p.eyeSpacing * s / 2 + gaze.dx * travel
            if p.caret < 0.99 {
                let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: min(w, h) / 2),
                       with: .color(FacePalette.eye.opacity(1 - p.caret).color))
            }
            if p.caret > 0.01 {
                var caret = Path()
                caret.move(to: CGPoint(x: x - w / 2, y: y + h / 2))
                caret.addLine(to: CGPoint(x: x, y: y - h / 2))
                caret.addLine(to: CGPoint(x: x + w / 2, y: y + h / 2))
                g.stroke(caret, with: .color(FacePalette.eye.opacity(p.caret).color),
                         style: StrokeStyle(lineWidth: 0.05 * s, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Blue "typing" badge at the top-left with three bouncing dots.
    private static func drawBadge(_ g: GraphicsContext, r: CGFloat, opacity: Double, t: Double) {
        let c = CGPoint(x: -0.7 * r, y: -0.7 * r)
        let br = 0.3 * r
        let rect = CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br)
        g.fill(Circle().path(in: rect.insetBy(dx: -0.06 * r, dy: -0.06 * r)), with: .color(RGBA.black.opacity(opacity * 0.85).color))
        g.fill(Circle().path(in: rect), with: .color(FacePalette.badge.opacity(opacity).color))

        let dot = 0.06 * r
        for i in 0..<3 {
            let dx = CGFloat(i - 1) * 0.15 * r
            let dy = -0.06 * r * max(0, sin(t * 2 * .pi * 1.8 - Double(i) * 0.7))
            g.fill(Circle().path(in: CGRect(x: c.x + dx - dot, y: c.y + dy - dot, width: 2 * dot, height: 2 * dot)),
                   with: .color(RGBA.white.opacity(opacity).color))
        }
    }

    /// Three four-pointed stars twinkling around the face.
    private static func drawSparkles(_ g: GraphicsContext, r: CGFloat, opacity: Double, t: Double) {
        let spots: [(angle: Double, distance: CGFloat, size: CGFloat)] = [(-2.3, 1.22, 0.22), (-0.6, 1.25, 0.17), (2.6, 1.2, 0.14)]
        for (i, spot) in spots.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(t * 4 + Double(i) * 2.1)
            let c = CGPoint(x: cos(spot.angle) * spot.distance * r, y: sin(spot.angle) * spot.distance * r)
            let a = spot.size * r * (0.6 + 0.4 * twinkle)
            var star = Path()
            star.move(to: CGPoint(x: c.x, y: c.y - a))
            star.addQuadCurve(to: CGPoint(x: c.x + a, y: c.y), control: c)
            star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + a), control: c)
            star.addQuadCurve(to: CGPoint(x: c.x - a, y: c.y), control: c)
            star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - a), control: c)
            g.fill(star, with: .color(FacePalette.sparkle.opacity(opacity * (0.5 + 0.5 * twinkle)).color))
        }
    }

    /// "z"s drifting up from the top-right, staggered.
    private static func drawZzz(_ g: GraphicsContext, r: CGFloat, opacity: Double, t: Double) {
        let cycle = 2.4
        for i in 0..<3 {
            let phase = (t + Double(i) * cycle / 3).truncatingRemainder(dividingBy: cycle) / cycle
            let fade = sin(.pi * phase)
            let size = (0.3 + 0.25 * phase) * r
            let point = CGPoint(x: (0.75 + 0.35 * phase) * r, y: (-0.65 - 0.6 * phase) * r)
            let text = Text("z").font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(RGBA.white.opacity(opacity * fade * 0.9).color)
            g.draw(text, at: point)
        }
    }
}
