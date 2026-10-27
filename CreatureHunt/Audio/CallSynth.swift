import AVFoundation

enum CallKind: CaseIterable {
  case chirp, hoot, rustle, bubble, tick, croak
}

/// Generates every sound in the game in code, so there are no audio files to license or ship.
/// Same recipes as the web prototype.
enum CallSynth {
  static let sampleRate: Double = 44_100

  static func buffer(for kind: CallKind, format: AVAudioFormat) -> AVAudioPCMBuffer {
    var s = SampleBuffer(seconds: 1.1)
    switch kind {
    case .chirp:
      for i in 0..<3 {
        s.tone(.sine, from: 2300, to: 3600, glide: 0.07, at: 0.02 + Double(i) * 0.12, duration: 0.09, peak: 0.5)
      }
    case .hoot:
      s.tone(.triangle, from: 400, at: 0.02, duration: 0.3, peak: 0.7, attack: 0.05, vibratoHz: 6, vibratoDepth: 7)
      s.tone(.triangle, from: 330, at: 0.40, duration: 0.5, peak: 0.7, attack: 0.05, vibratoHz: 6, vibratoDepth: 7)
    case .rustle:
      for i in 0..<4 {
        s.noise(
          at: 0.02 + Double(i) * 0.07 + .random(in: 0...0.04), duration: .random(in: 0.05...0.1),
          peak: 0.9, center: .random(in: 2500...5000), q: 0.9)
      }
    case .bubble:
      for i in 0..<4 {
        s.tone(
          .sine, from: .random(in: 700...1100), to: 240, glide: 0.07,
          at: 0.02 + Double(i) * 0.09 + .random(in: 0...0.03), duration: 0.08, peak: 0.55, attack: 0.004)
      }
    case .tick:
      for i in 0..<4 {
        s.tone(.square, from: i % 2 == 0 ? 1800 : 1300, at: 0.02 + Double(i) * 0.18, duration: 0.035, peak: 0.22, attack: 0.002)
      }
    case .croak:
      for start in [0.02, 0.47] {
        s.tone(
          .saw, from: 130, to: 105, glide: 0.35, at: start, duration: 0.38, peak: 0.8, attack: 0.03,
          amHz: 26, lowpass: 850)
      }
    }
    return s.makeBuffer(format: format, normalizeTo: 0.8)
  }

  /// The little rising arpeggio when you catch something.
  static func jingle(format: AVAudioFormat) -> AVAudioPCMBuffer {
    var s = SampleBuffer(seconds: 0.6)
    for (i, f) in [660.0, 880, 1320].enumerated() {
      s.tone(.sine, from: f, at: 0.01 + Double(i) * 0.08, duration: 0.28, peak: 0.22)
    }
    return s.makeBuffer(format: format, normalizeTo: nil)
  }
}

private struct SampleBuffer {
  enum Wave { case sine, triangle, square, saw }

  var data: [Float]

  init(seconds: Double) {
    data = .init(repeating: 0, count: Int(seconds * CallSynth.sampleRate))
  }

  mutating func tone(
    _ wave: Wave, from f0: Double, to f1: Double? = nil, glide: Double = 0,
    at start: Double, duration: Double, peak: Double, attack: Double = 0.01,
    vibratoHz: Double = 0, vibratoDepth: Double = 0, amHz: Double = 0, lowpass: Double? = nil
  ) {
    let sr = CallSynth.sampleRate
    let first = Int(start * sr)
    let count = Int(duration * sr)
    let lpCoefficient = lowpass.map { 1 - exp(-2 * Double.pi * $0 / sr) }
    var phase = 0.0
    var filtered = 0.0
    for i in 0..<count {
      let index = first + i
      guard index < data.count else { break }
      let t = Double(i) / sr
      var f = f0
      if let f1, glide > 0 { f = f0 * pow(f1 / f0, min(1, t / glide)) }
      if vibratoHz > 0 { f += vibratoDepth * sin(2 * .pi * vibratoHz * t) }
      phase += 2 * .pi * f / sr
      var v: Double
      switch wave {
      case .sine: v = sin(phase)
      case .triangle: v = 2 / Double.pi * asin(sin(phase))
      case .square: v = sin(phase) >= 0 ? 1 : -1
      case .saw:
        let x = phase / (2 * .pi)
        v = 2 * (x - (x + 0.5).rounded(.down))
      }
      if let a = lpCoefficient {
        filtered += a * (v - filtered)
        v = filtered
      }
      if amHz > 0 { v *= 0.5 + 0.5 * sin(2 * .pi * amHz * t) }
      data[index] += Float(v * envelope(t, peak: peak, attack: attack, duration: duration))
    }
  }

  /// White noise through a band-pass filter: leaves, wings, rustling.
  mutating func noise(at start: Double, duration: Double, peak: Double, center: Double, q: Double) {
    let sr = CallSynth.sampleRate
    // RBJ band-pass biquad (constant 0 dB peak gain).
    let w0 = 2 * Double.pi * center / sr
    let alpha = sin(w0) / (2 * q)
    let a0 = 1 + alpha
    let b0 = alpha / a0, b2 = -alpha / a0
    let a1 = -2 * cos(w0) / a0, a2 = (1 - alpha) / a0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    let first = Int(start * sr)
    for i in 0..<Int(duration * sr) {
      let index = first + i
      guard index < data.count else { break }
      let x = Double.random(in: -1...1)
      let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
      x2 = x1; x1 = x; y2 = y1; y1 = y
      let t = Double(i) / sr
      data[index] += Float(y * 3 * envelope(t, peak: peak, attack: 0.005, duration: duration))
    }
  }

  /// Linear attack, then an exponential fade to silence.
  private func envelope(_ t: Double, peak: Double, attack: Double, duration: Double) -> Double {
    if t < attack { return peak * t / attack }
    let progress = (t - attack) / max(0.0001, duration - attack)
    return peak * pow(0.0001 / peak, progress)
  }

  func makeBuffer(format: AVAudioFormat, normalizeTo target: Float?) -> AVAudioPCMBuffer {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count))!
    buffer.frameLength = buffer.frameCapacity
    var scale: Float = 1
    if let target, let loudest = data.map({ abs($0) }).max(), loudest > 0 { scale = target / loudest }
    let channel = buffer.floatChannelData![0]
    for i in 0..<data.count { channel[i] = data[i] * scale }
    return buffer
  }
}
