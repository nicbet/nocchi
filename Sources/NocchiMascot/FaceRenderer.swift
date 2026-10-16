import CoreGraphics

/// Draws one face with Core Graphics, in a y-down context whose size is the canvas (larger than
/// the face, see `FaceView.canvasScale`, so the ring, badge and sparkles have room).
/// Used by the live `FaceNSView` and, through `Canvas.withCGContext`, by still frames and snapshots.
public enum FaceRenderer {
    /// Faces smaller than this don't breathe: sub-point scaling only shimmers.
    public static let minimumBreathingSize: CGFloat = 32

    public static func draw(
        in cg: CGContext,
        canvas: CGSize,
        size s: CGFloat,
        params p: FaceParams,
        gaze: CGVector,
        t: Double
    ) {
        cg.saveGState()
        defer { cg.restoreGState() }

        let r = s / 2
        cg.translateBy(x: canvas.width / 2 + p.offset.dx * s, y: canvas.height / 2 + p.offset.dy * s)
        cg.rotate(by: p.rotation)
        let scale = s < minimumBreathingSize ? 1 : p.scale
        cg.scaleBy(x: scale, y: scale)

        // Amber "needs you" ring.
        if p.ring > 0.01 {
            let rr = r + 0.09 * s
            cg.setStrokeColor(FacePalette.ring.opacity(p.ring).cgColor)
            cg.setLineWidth(0.06 * s)
            cg.strokeEllipse(in: CGRect(x: -rr, y: -rr, width: 2 * rr, height: 2 * rr))
        }

        // Body: soft radial shading in the mood's color.
        let body = p.body
        let bodyRect = CGRect(x: -r, y: -r, width: s, height: s)
        cg.saveGState()
        cg.addEllipse(in: bodyRect)
        cg.clip()
        let light = CGPoint(x: -0.3 * r, y: -0.35 * r)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [body.lighter(0.35).cgColor, body.cgColor, body.darker(0.18).cgColor] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            cg.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: light, endRadius: 1.5 * r,
                                  options: [.drawsAfterEndLocation])
        }
        cg.restoreGState()

        drawEyes(cg, s: s, p: p, gaze: gaze)

        if p.errorDot > 0.01 {
            // Deep red dot sitting on the rim at the top-left, with a soft glow instead of an outline.
            let d = 0.17 * s
            let c = CGPoint(x: -0.67 * r, y: -0.67 * r)  // on the rim at -135°
            let dot = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 0.1 * s, color: FacePalette.errorDot.opacity(0.8 * p.errorDot).cgColor)
            cg.setFillColor(FacePalette.errorDot.opacity(p.errorDot).cgColor)
            cg.fillEllipse(in: dot)
            cg.restoreGState()
        }
        if p.badge > 0.01 { drawBadge(cg, r: r, opacity: p.badge, t: t) }
        if p.sparkles > 0.01 { drawSparkles(cg, r: r, opacity: p.sparkles, t: t) }
        if p.zzz > 0.01 { drawZzz(cg, r: r, opacity: p.zzz, t: t) }
    }

    /// How far the eyes travel at full gaze, in points.
    public static func eyeTravel(size s: CGFloat) -> CGFloat { 0.07 * s }

    private static func drawEyes(_ cg: CGContext, s: CGFloat, p: FaceParams, gaze: CGVector) {
        let travel = eyeTravel(size: s)
        let y = p.eyeY * s + gaze.dy * travel
        let w = p.eyeWidth * s
        let h = max(p.eyeHeight * s, 0.02 * s)

        for side in [-1.0, 1.0] {
            let x = side * p.eyeSpacing * s / 2 + gaze.dx * travel
            if p.caret < 0.99 {
                let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                let corner = min(w, h) / 2
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
                cg.setFillColor(FacePalette.eye.opacity(1 - p.caret).cgColor)
                cg.fillPath()
            }
            if p.caret > 0.01 {
                cg.move(to: CGPoint(x: x - w / 2, y: y + h / 2))
                cg.addLine(to: CGPoint(x: x, y: y - h / 2))
                cg.addLine(to: CGPoint(x: x + w / 2, y: y + h / 2))
                cg.setStrokeColor(FacePalette.eye.opacity(p.caret).cgColor)
                cg.setLineWidth(0.05 * s)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.strokePath()
            }
        }
    }

    /// Dark "typing" badge at the top-left with three bouncing dots.
    private static func drawBadge(_ cg: CGContext, r: CGFloat, opacity: Double, t: Double) {
        let c = CGPoint(x: -0.7 * r, y: -0.7 * r)
        let br = 0.3 * r
        let rect = CGRect(x: c.x - br, y: c.y - br, width: 2 * br, height: 2 * br)
        cg.setFillColor(RGBA.black.opacity(opacity * 0.85).cgColor)
        cg.fillEllipse(in: rect.insetBy(dx: -0.06 * r, dy: -0.06 * r))
        cg.setFillColor(FacePalette.badge.opacity(opacity).cgColor)
        cg.fillEllipse(in: rect)

        let dot = 0.06 * r
        cg.setFillColor(RGBA.white.opacity(opacity).cgColor)
        for i in 0..<3 {
            let dx = CGFloat(i - 1) * 0.15 * r
            let dy = -0.06 * r * max(0, sin(t * 2 * .pi * 1.8 - Double(i) * 0.7))
            cg.fillEllipse(in: CGRect(x: c.x + dx - dot, y: c.y + dy - dot, width: 2 * dot, height: 2 * dot))
        }
    }

    /// Three four-pointed stars twinkling around the face.
    private static func drawSparkles(_ cg: CGContext, r: CGFloat, opacity: Double, t: Double) {
        let spots: [(angle: Double, distance: CGFloat, size: CGFloat)] = [(-2.3, 1.22, 0.22), (-0.6, 1.25, 0.17), (2.6, 1.2, 0.14)]
        for (i, spot) in spots.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(t * 4 + Double(i) * 2.1)
            let c = CGPoint(x: cos(spot.angle) * spot.distance * r, y: sin(spot.angle) * spot.distance * r)
            let a = spot.size * r * (0.6 + 0.4 * twinkle)
            cg.move(to: CGPoint(x: c.x, y: c.y - a))
            cg.addQuadCurve(to: CGPoint(x: c.x + a, y: c.y), control: c)
            cg.addQuadCurve(to: CGPoint(x: c.x, y: c.y + a), control: c)
            cg.addQuadCurve(to: CGPoint(x: c.x - a, y: c.y), control: c)
            cg.addQuadCurve(to: CGPoint(x: c.x, y: c.y - a), control: c)
            cg.setFillColor(FacePalette.sparkle.opacity(opacity * (0.5 + 0.5 * twinkle)).cgColor)
            cg.fillPath()
        }
    }

    /// "z"s drifting up from the top-right, staggered. Drawn as strokes, not text.
    private static func drawZzz(_ cg: CGContext, r: CGFloat, opacity: Double, t: Double) {
        let cycle = 2.4
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        for i in 0..<3 {
            let phase = (t + Double(i) * cycle / 3).truncatingRemainder(dividingBy: cycle) / cycle
            let fade = sin(.pi * phase)
            let half = (0.3 + 0.25 * phase) * r * 0.36
            let c = CGPoint(x: (0.75 + 0.35 * phase) * r, y: (-0.65 - 0.6 * phase) * r)
            cg.move(to: CGPoint(x: c.x - half, y: c.y - half))
            cg.addLine(to: CGPoint(x: c.x + half, y: c.y - half))
            cg.addLine(to: CGPoint(x: c.x - half, y: c.y + half))
            cg.addLine(to: CGPoint(x: c.x + half, y: c.y + half))
            cg.setStrokeColor(RGBA.white.opacity(opacity * fade * 0.9).cgColor)
            cg.setLineWidth(max(0.6, half * 0.45))
            cg.strokePath()
        }
    }
}
