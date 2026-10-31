// Synthesizes Sway's break sounds into Resources/Sounds/*.m4a.
// Run from the repository root: swift tools/sounds.swift
//
// Each sound is a few soft mallet notes (a sine with a quiet overtone or two and a quick
// attack) over the cat's purr, through a small room reverb, kept low and warm so it never startles.
import Foundation

let rate = 44_100.0

struct Note {
    var at: Double        // seconds from the start
    var frequency: Double
    var gain: Double
    var decay: Double     // seconds for the note to fall to about a third
}

/// A pitch from its name, e.g. "A4" = 440 Hz.
func pitch(_ name: String) -> Double {
    let steps = ["C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2]
    let octave = Int(String(name.last!))!
    var semitones = steps[String(name.first!)]! + (octave - 4) * 12
    if name.contains("#") { semitones += 1 }
    return 440 * pow(2, Double(semitones) / 12)
}

/// Mallet tone: the fundamental plus a soft octave and a faint bell-like partial.
func render(_ notes: [Note], seconds: Double, pad: (frequency: Double, gain: Double)? = nil) -> [Double] {
    var samples = [Double](repeating: 0, count: Int(seconds * rate))
    let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1, 1, 1), (2, 0.22, 0.55), (3.01, 0.06, 0.3), (4.2, 0.025, 0.2)]
    for note in notes {
        let start = Int(note.at * rate)
        for i in start..<samples.count {
            let t = Double(i - start) / rate
            let attack = 1 - exp(-t / 0.006)
            var value = 0.0
            for partial in partials where note.frequency * partial.ratio < 12_000 {
                value += partial.gain * exp(-t / (note.decay * partial.decay)) * sin(2 * .pi * note.frequency * partial.ratio * t)
            }
            samples[i] += note.gain * attack * value
        }
    }
    // An optional low hum that swells in and fades out under the notes.
    if let pad {
        for i in samples.indices {
            let t = Double(i) / rate
            let swell = sin(.pi * min(1, t / seconds))
            samples[i] += pad.gain * swell * swell * (sin(2 * .pi * pad.frequency * t) + 0.3 * sin(2 * .pi * pad.frequency * 1.5 * t))
        }
    }
    return samples
}

/// A cat's purr: a rattle of about 25 pulses a second, each a short burst of filtered noise,
/// louder breathing out than in. `breaths` lists when each breath starts and whether it's out.
func purr(seconds: Double, gain: Double, breaths: [(at: Double, out: Bool)]) -> [Double] {
    var samples = [Double](repeating: 0, count: Int(seconds * rate))
    var generator = SystemRandomNumberGenerator()
    // Two-pole filters: a resonance for the throat, then a lowpass to keep it soft.
    func biquad(_ x: [Double], frequency: Double, q: Double, bandpass: Bool) -> [Double] {
        let w = 2 * .pi * frequency / rate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        let b = bandpass ? [alpha / a0, 0, -alpha / a0] : [(1 - cos(w)) / 2 / a0, (1 - cos(w)) / a0, (1 - cos(w)) / 2 / a0]
        let a1 = -2 * cos(w) / a0, a2 = (1 - alpha) / a0
        var y = [Double](repeating: 0, count: x.count), x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            y[i] = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = y[i]
        }
        return y
    }
    for (index, breath) in breaths.enumerated() {
        let end = index + 1 < breaths.count ? breaths[index + 1].at : seconds
        let length = end - breath.at - 0.08  // A short catch of breath between in and out.
        let rateHz = breath.out ? 24.0 : 27.0
        let level = breath.out ? 1.0 : 0.6
        var phase = 0.0
        for i in Int(breath.at * rate)..<min(samples.count, Int((breath.at + length) * rate)) {
            let t = Double(i) / rate - breath.at
            // Swells in and eases out over the breath, with a slight wobble in the pulse rate.
            let shape = pow(sin(.pi * min(1, t / length)), 0.6)
            phase += (rateHz + 1.5 * sin(2 * .pi * 0.7 * t)) / rate
            let pulse = exp(-phase.truncatingRemainder(dividingBy: 1) / 0.18)
            let noise = Double.random(in: -1...1, using: &generator)
            samples[i] = level * shape * pulse * (noise + 0.8 * sin(2 * .pi * rateHz * 2 * t))
        }
    }
    let throat = biquad(samples, frequency: 220, q: 1.2, bandpass: true)
    let soft = biquad(samples, frequency: 700, q: 0.7, bandpass: false)
    let mixed = samples.indices.map { throat[$0] * 1.5 + soft[$0] }
    let loudest = mixed.map(abs).max() ?? 1
    return mixed.map { $0 / loudest * gain }
}

func mix(_ a: [Double], _ b: [Double]) -> [Double] {
    var out = [Double](repeating: 0, count: max(a.count, b.count))
    for (i, x) in a.enumerated() { out[i] += x }
    for (i, x) in b.enumerated() { out[i] += x }
    return out
}

/// A small Schroeder reverb: four damped combs in parallel, then two allpasses.
func reverb(_ dry: [Double], wet: Double) -> [Double] {
    var combed = [Double](repeating: 0, count: dry.count)
    for delay in [1557, 1617, 1491, 1422] {
        var buffer = [Double](repeating: 0, count: delay)
        var index = 0, low = 0.0
        for i in dry.indices {
            let out = buffer[index]
            low = out * 0.6 + low * 0.4
            buffer[index] = dry[i] + low * 0.8
            index = (index + 1) % delay
            combed[i] += out / 4
        }
    }
    for delay in [225, 556] {
        var buffer = [Double](repeating: 0, count: delay)
        var index = 0
        for i in combed.indices {
            let delayed = buffer[index]
            let input = combed[i]
            buffer[index] = input + delayed * 0.5
            combed[i] = delayed - input * 0.5
            index = (index + 1) % delay
        }
    }
    return dry.indices.map { dry[$0] * (1 - wet) + combed[$0] * wet }
}

/// Scales to `peak` (0...1), fades the tail out and writes a 16-bit mono WAV, then an AAC .m4a.
func save(_ samples: [Double], peak: Double, name: String) throws {
    let loudest = samples.map(abs).max() ?? 1
    let fade = Int(0.3 * rate)
    let pcm: [Int16] = samples.enumerated().map { i, sample in
        let tail = min(1, Double(samples.count - i) / Double(fade))
        return Int16(max(-1, min(1, sample / loudest * peak * tail)) * 32_767)
    }
    var wav = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
    wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count * 2))
    wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
    wav.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count * 2))
    for sample in pcm { append(sample) }

    let directory = URL(fileURLWithPath: "Resources/Sounds")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
    try wav.write(to: temporary)
    let convert = Process()
    convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    convert.arguments = ["-f", "m4af", "-d", "aac", "-b", "96000", temporary.path,
                         directory.appendingPathComponent("\(name).m4a").path]
    try convert.run()
    convert.waitUntilExit()
    try FileManager.default.removeItem(at: temporary)
    print("Resources/Sounds/\(name).m4a")
}

// Heads-up: two quiet notes rising a fifth over one purring breath, a polite "soon".
try save(reverb(mix(render([
    Note(at: 0.02, frequency: pitch("D5"), gain: 0.8, decay: 0.7),
    Note(at: 0.24, frequency: pitch("A5"), gain: 0.7, decay: 0.9),
], seconds: 1.8), purr(seconds: 1.8, gain: 0.9, breaths: [(0, true)])), wet: 0.25), peak: 0.45, name: "heads-up")

// Break starts: a slow, open arpeggio over a low hum and a few purring breaths, settling the room down.
try save(reverb(mix(render([
    Note(at: 0.05, frequency: pitch("C5"), gain: 0.8, decay: 1.6),
    Note(at: 0.35, frequency: pitch("G5"), gain: 0.6, decay: 1.6),
    Note(at: 0.65, frequency: pitch("E5"), gain: 0.65, decay: 1.8),
    Note(at: 0.95, frequency: pitch("D6"), gain: 0.4, decay: 2.0),
], seconds: 4.2, pad: (pitch("C3"), 0.12)),
    purr(seconds: 4.2, gain: 1.0, breaths: [(0, true), (1.6, false), (2.6, true)])), wet: 0.3), peak: 0.55, name: "break-start")

// Break's over: a quick, bright run up and a contented purr, a small cheer to get going again.
try save(reverb(mix(render([
    Note(at: 0.02, frequency: pitch("G5"), gain: 0.6, decay: 0.5),
    Note(at: 0.12, frequency: pitch("C6"), gain: 0.65, decay: 0.5),
    Note(at: 0.22, frequency: pitch("E6"), gain: 0.6, decay: 0.6),
    Note(at: 0.34, frequency: pitch("G6"), gain: 0.55, decay: 1.1),
    Note(at: 0.34, frequency: pitch("C6"), gain: 0.3, decay: 1.1),
], seconds: 2.2), purr(seconds: 2.2, gain: 0.9, breaths: [(0.3, true)])), wet: 0.25), peak: 0.55, name: "break-over")
