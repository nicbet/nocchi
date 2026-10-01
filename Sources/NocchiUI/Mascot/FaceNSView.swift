import AppKit
import NocchiCore

/// A live face drawn with Core Graphics, driven by its own display link. This keeps per-frame
/// work out of SwiftUI: a `TimelineView` tick re-lays out the whole hosting view, this only
/// redraws one small layer, and only when the picture actually changed.
final class FaceNSView: NSView {
    private var motion: FaceMotion
    private var color: RGBA
    private var size: CGFloat
    private var seed: Double
    private var frameRate: Double = 30
    private var paused = false
    private var reduceMotion = false

    private var link: CADisplayLink?
    private var frame_ = Frame(params: FaceParams(), gaze: .zero, t: 0)
    private var lastKey: [Double] = []

    private struct Frame {
        var params: FaceParams
        var gaze: CGVector
        var t: Double
    }

    init(mood: Mood, color: RGBA, size: CGFloat, seed: Double) {
        motion = FaceMotion(mood: mood)
        self.color = color
        self.size = size
        self.seed = seed
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(mood: Mood, color: RGBA, size: CGFloat, seed: Double, frameRate: Double, paused: Bool, reduceMotion: Bool) {
        let appearanceChanged = color != self.color || size != self.size || seed != self.seed || reduceMotion != self.reduceMotion
        motion.setMood(mood, at: CACurrentMediaTime())
        self.color = color
        self.size = size
        self.seed = seed
        self.reduceMotion = reduceMotion
        if frameRate != self.frameRate || paused != self.paused {
            self.frameRate = frameRate
            self.paused = paused
            updateLink()
        }
        update(force: appearanceChanged)
    }

    // MARK: Frame loop

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLink()
        update(force: true)
    }

    private func updateLink() {
        guard window != nil else {
            link?.invalidate()
            link = nil
            return
        }
        if link == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        let fps = Float(frameRate)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(10, fps), maximum: fps, preferred: fps)
        link?.isPaused = paused
    }

    @objc private func tick(_ link: CADisplayLink) {
        update(force: false)
    }

    /// Computes the current frame and redraws only if it differs visibly from the last one.
    private func update(force: Bool) {
        // While paused there are no ticks to play a transition, so show the new mood right away.
        let now = paused ? CACurrentMediaTime() + FaceMotion.transitionDuration : CACurrentMediaTime()
        let t = Date.timeIntervalSinceReferenceDate
        let params = motion.params(at: now, motionTime: t, seed: seed, reduceMotion: reduceMotion)
        let gaze = FaceMotion.gaze(params, pointer: pointerOffset(), size: size)
        frame_ = Frame(params: params, gaze: gaze, t: t)

        let key = renderKey(params, gaze: gaze, t: t)
        guard force || key != lastKey else { return }
        lastKey = key
        needsDisplay = true
    }

    /// The pointer relative to the face center, y down. `nil` outside a window.
    private func pointerOffset() -> CGVector? {
        guard let window else { return nil }
        let pointer = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        return CGVector(dx: pointer.x - center.x, dy: -(pointer.y - center.y))
    }

    /// What the face looks like, quantized to what's visible: quarter points for positions,
    /// small steps for angles and opacities. Accessories animate on their own clock, so while one
    /// is showing the key also includes `t` and the face redraws every tick.
    private func renderKey(_ p: FaceParams, gaze: CGVector, t: Double) -> [Double] {
        let animatesOnItsOwn = p.ring > 0.01 || p.badge > 0.01 || p.sparkles > 0.01 || p.zzz > 0.01
        let s = Double(size)
        let travel = Double(FaceRenderer.eyeTravel(size: size))
        func pt(_ x: Double) -> Double { (x * 4).rounded() }
        func step(_ x: Double, _ q: Double) -> Double { (x / q).rounded() }
        return [
            pt(p.offset.dx * s), pt(p.offset.dy * s), step(p.rotation, 0.005),
            size < FaceRenderer.minimumBreathingSize ? 1 : step(p.scale, 0.002),
            step(p.redness, 0.01), step(p.dim, 0.01),
            pt(p.eyeWidth * s), pt(p.eyeHeight * s), pt(p.eyeY * s), pt(p.eyeSpacing * s), step(p.caret, 0.01),
            pt(gaze.dx * travel), pt(gaze.dy * travel), step(p.errorDot, 0.01),
            step(p.ring, 0.01), step(p.badge, 0.01), step(p.sparkles, 0.01), step(p.zzz, 0.01),
            animatesOnItsOwn ? t : 0,
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        FaceRenderer.draw(in: cg, canvas: bounds.size, size: size, params: frame_.params,
                          color: color, gaze: frame_.gaze, t: frame_.t)
    }
}
