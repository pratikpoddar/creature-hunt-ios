import AVFoundation

/// Values shared with the real-time audio thread. Small races here are harmless (worst case a
/// frame of the old pitch), and avoiding locks keeps the audio thread safe.
private final class ToneState {
  var frequency: Double = 480
  var targetGain: Double = 0
  var gain: Double = 0
  var phase: Double = 0
}

/// Plays creature calls in 3D around the listener.
///
/// - The creature is a mono source placed around a listener who always faces forward (-Z);
///   the game moves the *source* by the angle between your heading and the creature.
/// - HRTF rendering gives left/right and some front/back; extra occlusion muffles sounds
///   behind you, which is the cue that tells you to turn around.
/// - A soft tone rises while you're locked on, and a jingle plays on a catch.
///
/// On Meta glasses this all plays through their open-ear speakers, because they're the
/// phone's Bluetooth audio output.
@MainActor
final class SpatialAudioEngine {
  private let engine = AVAudioEngine()
  private let environment = AVAudioEnvironmentNode()
  private let creaturePlayer = AVAudioPlayerNode()
  private let effectsPlayer = AVAudioPlayerNode()
  private let toneState = ToneState()
  private let format = AVAudioFormat(standardFormatWithSampleRate: CallSynth.sampleRate, channels: 1)!
  private var toneNode: AVAudioSourceNode?
  private var calls: [CallKind: [AVAudioPCMBuffer]] = [:]
  private var jingle: AVAudioPCMBuffer?
  private var isSetUp = false

  /// Distance of the creature from your head, in metres.
  private let distance: Float = 2.5

  func start() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
    if !isSetUp { setUp() }
    if !engine.isRunning { try engine.start() }
    if !creaturePlayer.isPlaying { creaturePlayer.play() }
    if !effectsPlayer.isPlaying { effectsPlayer.play() }
  }

  func pause() {
    engine.pause()
  }

  func playCall(_ kind: CallKind, volume: Float) {
    guard let buffer = calls[kind]?.randomElement() else { return }
    creaturePlayer.volume = volume
    creaturePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
  }

  /// - Parameter relativeAngle: Degrees from straight ahead, clockwise-positive.
  func updateSource(relativeAngle: Double) {
    let r = Deg.radians(relativeAngle)
    creaturePlayer.position = AVAudio3DPoint(
      x: Float(sin(r)) * distance, y: 0, z: -Float(cos(r)) * distance)
    // 1 straight ahead, 0 directly behind. Behind you sounds muffled and quieter.
    let front = (cos(r) + 1) / 2
    creaturePlayer.occlusion = Float(-30 * (1 - front * front))
  }

  /// 0 = not facing the creature, 1 = caught.
  func setFocus(_ focus: Double) {
    toneState.targetGain = focus > 0 ? 0.03 + focus * 0.06 : 0
    toneState.frequency = 480 + focus * 420
  }

  /// Stops any queued calls from the creature that was just caught.
  func silenceCreature() {
    creaturePlayer.stop()
    if engine.isRunning { creaturePlayer.play() }
  }

  func playJingle() {
    guard let jingle else { return }
    effectsPlayer.scheduleBuffer(jingle, at: nil, options: [], completionHandler: nil)
  }

  private func setUp() {
    for kind in CallKind.allCases {
      // A few variations of each call so they don't sound robotic.
      calls[kind] = (0..<3).map { _ in CallSynth.buffer(for: kind, format: format) }
    }
    jingle = CallSynth.jingle(format: format)

    let tone = Self.makeToneNode(state: toneState, format: format)
    toneNode = tone

    engine.attach(environment)
    engine.attach(creaturePlayer)
    engine.attach(effectsPlayer)
    engine.attach(tone)

    engine.connect(environment, to: engine.mainMixerNode, format: nil)
    // Mono into the environment node is what makes the source spatial.
    engine.connect(creaturePlayer, to: environment, format: format)
    engine.connect(effectsPlayer, to: engine.mainMixerNode, format: format)
    engine.connect(tone, to: engine.mainMixerNode, format: format)

    // These mixing properties apply to the connection, so set them after connecting.
    creaturePlayer.renderingAlgorithm = .HRTFHQ
    creaturePlayer.sourceMode = .spatializeIfMono
    creaturePlayer.reverbBlend = 0.15

    environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
    environment.distanceAttenuationParameters.referenceDistance = 1
    environment.distanceAttenuationParameters.maximumDistance = 20
    environment.reverbParameters.enable = true
    environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
    environment.reverbParameters.level = -12

    engine.prepare()
    isSetUp = true
  }

  /// A sine whose pitch and volume follow `toneState`, smoothed per sample to avoid clicks.
  /// `nonisolated` so the render block isn't tied to the main actor: it runs on the audio thread.
  private nonisolated static func makeToneNode(state: ToneState, format: AVAudioFormat) -> AVAudioSourceNode {
    let sampleRate = CallSynth.sampleRate
    return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      for frame in 0..<Int(frameCount) {
        state.gain += (state.targetGain - state.gain) * 0.002
        state.phase += 2 * .pi * state.frequency / sampleRate
        if state.phase > 2 * .pi { state.phase -= 2 * .pi }
        let value = Float(sin(state.phase) * state.gain)
        for buffer in buffers {
          buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
        }
      }
      return noErr
    }
  }
}
