import Foundation

/// Nocchi's own little voice: every sound is the name, "no-chee", said with a different
/// intonation, the way a Pokémon says its name. Formant synthesis (a buzzy voice source shaped
/// by gliding vowel resonances, a nasal "n", a noisy "ch"), so there are no audio files and
/// nothing borrowed.
public enum NocchiVoice: String, CaseIterable, Sendable {
    /// "no-CHEE!": up, then a happy little dip.
    case finished
    /// "no-chee?": rising at the end, a question.
    case needsYou
    /// "no-chee…": sinking.
    case failed
    /// "no-chee!": bright and bouncy, for hello.
    case hello

    static let sampleRate = 44_100.0

    /// Pitch (Hz) over the "o" and over the "ee", as points in 0…1 of each vowel.
    private var contour: (o: [Double], ee: [Double], eeLength: Double) {
        switch self {
        case .finished: ([430, 470], [560, 720, 640], 0.24)
        case .needsYou: ([420, 400], [470, 520, 760], 0.27)
        case .failed: ([470, 450], [430, 360, 280], 0.32)
        case .hello: ([480, 540], [640, 800, 760], 0.22)
        }
    }

    /// The sound as mono samples in -1…1.
    public func samples() -> [Float] {
        let (oPitch, eePitch, eeLength) = contour
        let phonemes: [Phoneme] = [
            Phoneme(.n, length: 0.05, pitch: [oPitch[0] * 0.92, oPitch[0]]),
            Phoneme(.o, length: 0.12, pitch: oPitch),
            Phoneme(.ch, length: 0.075, pitch: [eePitch[0]]),
            Phoneme(.ee, length: eeLength, pitch: eePitch),
        ]
        return Self.render(phonemes)
    }

    /// A 16-bit mono WAV of the sound, which `NSSound(data:)` plays.
    public func wav() -> Data {
        let pcm = samples().map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(Self.sampleRate)); append(UInt32(Self.sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        for sample in pcm { append(sample) }
        return data
    }

    // MARK: Formant synthesis

    enum Sound {
        case n, o, ch, ee

        /// Formants (Hz) and bandwidths, raised ~30% from an adult voice for a small creature.
        var formants: [(frequency: Double, bandwidth: Double)] {
            switch self {
            case .n: [(330, 120), (1500, 300), (3000, 400)]
            case .o: [(680, 110), (1150, 130), (3200, 250)]
            case .ch: [(400, 200), (2600, 400), (4200, 500)]
            case .ee: [(380, 80), (3300, 160), (4300, 260)]
            }
        }
        /// How loud the voice is, and the hiss.
        var voicing: Double {
            switch self {
            case .n: 0.35
            case .o, .ee: 1
            case .ch: 0
            }
        }
        var noise: Double { self == .ch ? 1 : 0 }
    }

    struct Phoneme {
        var sound: Sound
        var length: Double
        var pitch: [Double]
        init(_ sound: Sound, length: Double, pitch: [Double]) {
            self.sound = sound
            self.length = length
            self.pitch = pitch
        }
    }

    static func render(_ phonemes: [Phoneme]) -> [Float] {
        let tail = 0.06
        let total = phonemes.reduce(0) { $0 + $1.length } + tail
        let count = Int(total * sampleRate)
        var out = [Double](repeating: 0, count: count)
        var noise = SplitMix(seed: 0x6E6F6363)
        var formants = [Resonator](repeating: Resonator(), count: 3)
        var hiss = Resonator()
        var hissLow = Resonator()
        var phase = 0.0
        var previousHiss = 0.0
        let transition = 0.035  // vowels glide into each other over this long

        // Where each phoneme starts.
        var starts: [Double] = []
        var cursor = 0.0
        for phoneme in phonemes { starts.append(cursor); cursor += phoneme.length }

        func pitch(of phoneme: Phoneme, at progress: Double) -> Double {
            let points = phoneme.pitch
            guard points.count > 1 else { return points.first ?? 440 }
            let position = min(max(progress, 0), 1) * Double(points.count - 1)
            let index = min(Int(position), points.count - 2)
            let local = position - Double(index)
            // Smoothstep between points: sung, not stepped.
            let eased = local * local * (3 - 2 * local)
            return points[index] + (points[index + 1] - points[index]) * eased
        }

        for n in 0..<count {
            let t = Double(n) / sampleRate
            // The current phoneme and the next one, blended near the boundary.
            let index = max(0, (starts.lastIndex { $0 <= t } ?? 0))
            let phoneme = phonemes[min(index, phonemes.count - 1)]
            let local = t - starts[min(index, starts.count - 1)]
            let progress = local / phoneme.length
            let next = index + 1 < phonemes.count ? phonemes[index + 1] : nil
            let blend = next.map { _ in max(0, min(1, (local - (phoneme.length - transition)) / transition)) } ?? 0
            let target = next ?? phoneme
            func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * blend }

            // Voice source: band-limited sawtooth, with vibrato and a hint of jitter.
            var f0 = pitch(of: phoneme, at: progress)
            if let next, blend > 0 { f0 = lerp(f0, pitch(of: next, at: 0)) }
            f0 *= 1 + 0.018 * sin(2 * .pi * 5.5 * t) * min(1, t / 0.12) + 0.003 * (noise.next() - 0.5)
            phase += f0 / sampleRate
            if phase >= 1 { phase -= 1 }
            var source = 0.0
            let harmonics = Int(min(40, (sampleRate / 2 - 500) / f0))
            for k in 1...max(1, harmonics) {
                source += sin(2 * .pi * Double(k) * phase) / Double(k)
            }
            source *= 0.5

            // Loudness: past the last phoneme the voice rings out briefly.
            let after = t - cursor
            let release = after > 0 ? exp(-after / 0.02) : 1
            let voicing = lerp(phoneme.sound.voicing, target.sound.voicing) * release
            let noiseAmount = lerp(phoneme.sound.noise, target.sound.noise)

            // Vowel resonances, gliding between sounds.
            var voiced = source * voicing
            for (i, formant) in phoneme.sound.formants.enumerated() {
                let other = target.sound.formants[i]
                formants[i].tune(frequency: lerp(formant.frequency, other.frequency),
                                 bandwidth: lerp(formant.bandwidth, other.bandwidth), sampleRate: sampleRate)
                voiced = formants[i].process(voiced)
            }

            // "ch": a sharp onset (the t) then hiss (the sh), high and bright.
            var fricative = 0.0
            if noiseAmount > 0 {
                let white = noise.next() * 2 - 1
                let bright = white - previousHiss
                previousHiss = white
                hiss.tune(frequency: 3800, bandwidth: 1800, sampleRate: sampleRate)
                hissLow.tune(frequency: 2600, bandwidth: 1200, sampleRate: sampleRate)
                let onset = phoneme.sound == .ch ? 1 + 2.5 * exp(-local / 0.008) : 1
                fricative = (hiss.process(bright) + 0.5 * hissLow.process(bright)) * noiseAmount * onset * 0.35
            }

            // Overall envelope: a soft start so the "n" doesn't click.
            let start = min(1, t / 0.015)
            out[n] = (voiced + fricative) * start
        }

        // Normalize and fade the very end.
        let peak = out.map(abs).max() ?? 1
        let scale = peak > 0 ? 0.75 / peak : 1
        let fade = Int(0.012 * sampleRate)
        return out.enumerated().map { index, value in
            Float(value * scale * min(1, Double(out.count - index) / Double(fade)))
        }
    }

    /// A two-pole resonator (Klatt), the building block of formant synthesis.
    struct Resonator {
        var a = 1.0, b = 0.0, c = 0.0
        var y1 = 0.0, y2 = 0.0

        mutating func tune(frequency: Double, bandwidth: Double, sampleRate: Double) {
            let r = exp(-.pi * bandwidth / sampleRate)
            c = -r * r
            b = 2 * r * cos(2 * .pi * frequency / sampleRate)
            a = 1 - b - c
        }

        mutating func process(_ x: Double) -> Double {
            let y = a * x + b * y1 + c * y2
            y2 = y1
            y1 = y
            return y
        }
    }

    /// Deterministic noise, so a sound is the same every time.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }
}
