import Foundation

/// Nocchi's own little voice: every sound is the name, "no-chi", sung with a different
/// intonation, so it's recognisable without being loud or long. Synthesized here (additive
/// partials shaped like an "o" then an "i" vowel, a noise burst for the "ch"), so there are no
/// audio files and nothing borrowed.
public enum NocchiVoice: String, CaseIterable, Sendable {
    /// "no-CHI!": a bright rising fifth with a sparkle.
    case finished
    /// "no-chi?": the second syllable glides up, a question.
    case needsYou
    /// "no-chi…": falling and darker.
    case failed
    /// "no-cchi-i!": a three-note hello.
    case hello

    static let sampleRate = 44_100.0

    /// The sound as mono samples in -1…1.
    public func samples() -> [Float] {
        switch self {
        case .finished:
            return Self.mix([
                (0.00, Syllable(from: 659, to: 659, length: 0.11, vowel: .o)),
                (0.13, Syllable(from: 988, to: 1046, length: 0.17, vowel: .i, consonant: true)),
                (0.16, Syllable(from: 2637, to: 2637, length: 0.30, vowel: .bell, gain: 0.18)),
            ])
        case .needsYou:
            return Self.mix([
                (0.00, Syllable(from: 440, to: 440, length: 0.12, vowel: .o)),
                (0.14, Syllable(from: 554, to: 784, length: 0.24, vowel: .i, consonant: true)),
            ])
        case .failed:
            return Self.mix([
                (0.00, Syllable(from: 523, to: 523, length: 0.14, vowel: .o, gain: 0.8)),
                (0.16, Syllable(from: 440, to: 330, length: 0.28, vowel: .o, consonant: true, gain: 0.75)),
            ])
        case .hello:
            return Self.mix([
                (0.00, Syllable(from: 523, to: 523, length: 0.10, vowel: .o)),
                (0.12, Syllable(from: 784, to: 784, length: 0.10, vowel: .i, consonant: true)),
                (0.24, Syllable(from: 1046, to: 1175, length: 0.20, vowel: .i)),
                (0.27, Syllable(from: 3136, to: 3136, length: 0.30, vowel: .bell, gain: 0.15)),
            ])
        }
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

    // MARK: Synthesis

    enum Vowel {
        /// Round and dark: mostly the fundamental.
        case o
        /// Bright: upper partials.
        case i
        /// A bell-like sparkle: inharmonic partials, long decay.
        case bell

        var partials: [(ratio: Double, weight: Double)] {
            switch self {
            case .o: [(1, 1), (2, 0.45), (3, 0.12), (4, 0.04)]
            case .i: [(1, 0.8), (2, 0.25), (3, 0.38), (4, 0.22), (5, 0.12)]
            case .bell: [(1, 1), (2.76, 0.4), (5.4, 0.2)]
            }
        }
    }

    struct Syllable {
        var from: Double
        var to: Double
        var length: Double
        var vowel: Vowel
        /// Starts with a short "ch" noise burst.
        var consonant = false
        var gain = 1.0
    }

    static func mix(_ syllables: [(start: Double, syllable: Syllable)]) -> [Float] {
        let end = syllables.map { $0.start + $0.syllable.length + 0.05 }.max() ?? 0
        var out = [Double](repeating: 0, count: Int(end * sampleRate))
        var noise = SplitMix(seed: 0x6E6F6363)
        for (start, syllable) in syllables {
            let offset = Int(start * sampleRate)
            let count = Int(syllable.length * sampleRate)
            var phases = [Double](repeating: 0, count: syllable.vowel.partials.count)
            var previousNoise = 0.0
            for n in 0..<count where offset + n < out.count {
                let t = Double(n) / sampleRate
                let progress = t / syllable.length
                // Pitch glides along an ease-out curve, with a little vibrato once it's sung.
                let glide = 1 - pow(1 - progress, 2)
                let vibrato = 1 + 0.012 * sin(2 * .pi * 6 * t) * min(1, t / 0.08)
                let pitch = (syllable.from + (syllable.to - syllable.from) * glide) * vibrato
                // Soft attack, then a decay that a bell rings out longer.
                let attack = min(1, t / (syllable.vowel == .bell ? 0.004 : 0.012))
                let decay = syllable.vowel == .bell ? exp(-t / 0.09) : pow(1 - progress, 1.6)
                var sample = 0.0
                for (index, partial) in syllable.vowel.partials.enumerated() {
                    phases[index] += 2 * .pi * pitch * partial.ratio / sampleRate
                    sample += sin(phases[index]) * partial.weight
                }
                sample *= attack * decay * syllable.gain * 0.32
                if syllable.consonant, t < 0.035 {
                    // "ch": brightened noise (a first difference), quickly gone.
                    let white = noise.next() * 2 - 1
                    let bright = white - previousNoise
                    previousNoise = white
                    sample += bright * 0.05 * exp(-t / 0.012)
                }
                out[offset + n] += sample
            }
        }
        // Normalize gently and fade the very end.
        let peak = out.map(abs).max() ?? 1
        let scale = peak > 0 ? 0.7 / peak : 1
        let fade = Int(0.01 * sampleRate)
        return out.enumerated().map { index, value in
            let tail = min(1, Double(out.count - index) / Double(fade))
            return Float(value * scale * tail)
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
