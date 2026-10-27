import QuartzCore
import SwiftUI

enum HeadingSource: String, CaseIterable, Identifiable {
  case glasses = "Glasses"
  case phone = "Phone"
  case touch = "Touch"
  var id: String { rawValue }
}

/// The whole game: where you're facing, where the creature is, and the catch logic.
/// Ticks once per screen refresh.
@MainActor
final class GameEngine: ObservableObject {
  enum Phase { case intro, playing, caught, done }

  struct Catch: Identifiable {
    let id = UUID()
    let creature: Creature
    let angle: Double
    let seconds: Double
  }

  static let creaturesPerHunt = 5
  /// Seconds you must keep facing a creature to catch it.
  static let holdTime = 1.1
  /// Degrees per second when using the turn buttons.
  static let buttonTurnSpeed = 120.0

  @Published private(set) var phase: Phase = .intro
  @Published private(set) var yaw: Double = 0
  @Published private(set) var focus: Double = 0
  @Published private(set) var catches: [Catch] = []
  @Published private(set) var lastCatch: Catch?
  @Published private(set) var index = 0
  @Published private(set) var tolerance: Double = 14
  @Published private(set) var hintAngle: Double?
  @Published private(set) var elapsed: Double = 0
  @Published private(set) var penalty: Double = 0
  @Published private(set) var status = "Ready when you are."
  @Published private(set) var best: Double? = UserDefaults.standard.object(forKey: "creatureHunt.best") as? Double
  @Published private(set) var isNewBest = false
  @Published var source: HeadingSource = .touch {
    didSet { if source != oldValue { switchSource(from: oldValue) } }
  }

  /// Open-ear speakers blur direction more than headphones. This widens how far off-centre
  /// you can be and still lock on. Remembered between launches.
  @Published var wideCatch = UserDefaults.standard.bool(forKey: "creatureHunt.wideCatch") {
    didSet {
      UserDefaults.standard.set(wideCatch, forKey: "creatureHunt.wideCatch")
      if let current { tolerance = catchAngle(for: current.difficulty) }
    }
  }

  /// -1, 0 or +1 while a turn button is held.
  var manualTurn: Double = 0

  private static let bestKey = "creatureHunt.best"

  private struct Active {
    let creature: Creature
    let difficulty: Difficulty
    var angle: Double
    var drift: Double
    var flipAt: CFTimeInterval
    var nextCall: CFTimeInterval
    let startedAt: CFTimeInterval
  }

  private let glasses: GlassesManager
  private let phone = PhoneHeading()
  private let audio = SpatialAudioEngine()
  private var manualOffset: Double = 0
  private var hunt: [Creature] = []
  private var current: Active?
  private var hintUntil: CFTimeInterval = 0
  private var lastTick: CFTimeInterval = 0
  private var displayLink: CADisplayLink?
  /// Whether the glasses' display currently says "Hold steady". Has hysteresis so the screen
  /// isn't resent every time focus flickers.
  private var hudLocking = false

  init(glasses: GlassesManager) {
    self.glasses = glasses
    let target = DisplayLinkTarget { [weak self] timestamp in
      MainActor.assumeIsolated { self?.tick(now: timestamp) }
    }
    let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link

    // Buttons pressed on Display glasses.
    glasses.onHUDAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .start:
        if self.phase == .intro || self.phase == .done { self.startHunt() }
      case .hint:
        self.useHint()
      }
    }
    publishHUD()
  }

  // MARK: - Controls

  func startHunt() {
    do {
      try audio.start()
    } catch {
      status = "Audio couldn’t start: \(error.localizedDescription)"
      return
    }
    hunt = Array(Creature.all.shuffled().prefix(Self.creaturesPerHunt))
    index = 0
    catches = []
    penalty = 0
    focus = 0
    lastCatch = nil
    isNewBest = false
    phase = .playing
    spawn(now: CACurrentMediaTime())
  }

  /// Turns by a number of degrees, e.g. from dragging the ring.
  func nudge(by degrees: Double) {
    manualOffset += degrees
  }

  /// Briefly shows where the current creature is, at a 5 second cost.
  func useHint() {
    guard phase == .playing, var active = current else { return }
    let now = CACurrentMediaTime()
    penalty += 5
    hintUntil = now + 1.2
    active.nextCall = now
    current = active
  }

  func setActive(_ active: Bool) {
    if active {
      if phase == .playing || phase == .caught { try? audio.start() }
    } else {
      audio.pause()
    }
  }

  // MARK: - Heading

  private func rawHeading() -> Double {
    switch source {
    case .glasses: return glasses.yaw
    case .phone: return phone.yaw
    case .touch: return 0
    }
  }

  /// Switching sources keeps you facing the same way, so the creature doesn't jump.
  private func switchSource(from old: HeadingSource) {
    let facing = yaw
    switch old {
    case .glasses: glasses.stopTracking()
    case .phone: phone.stop()
    case .touch: break
    }
    switch source {
    case .glasses: glasses.startTracking()
    case .phone: phone.start()
    case .touch: break
    }
    manualOffset = facing - rawHeading()
  }

  // MARK: - Game loop

  private func tick(now: CFTimeInterval) {
    let dt = lastTick == 0 ? 0 : min(0.05, now - lastTick)
    lastTick = now

    if manualTurn != 0 { manualOffset += manualTurn * Self.buttonTurnSpeed * dt }
    let newYaw = Deg.wrap(rawHeading() + manualOffset)
    if abs(Deg.wrap(newYaw - yaw)) > 0.05 { yaw = newYaw }

    guard phase == .playing, var active = current else { return }

    if active.drift != 0 {
      if now > active.flipAt {
        active.drift = -active.drift
        active.flipAt = now + .random(in: 3...6)
      }
      active.angle = Deg.wrap(active.angle + active.drift * dt)
    }

    if now >= active.nextCall {
      audio.playCall(active.creature.call, volume: active.difficulty.volume)
      active.nextCall = now + active.difficulty.interval * .random(in: 0.85...1.15)
    }

    let relative = Deg.wrap(active.angle - yaw)
    audio.updateSource(relativeAngle: relative)

    if abs(relative) <= catchAngle(for: active.difficulty) {
      focus = min(1, focus + dt / Self.holdTime)
    } else if focus > 0 {
      focus = max(0, focus - dt * 1.2)
    }
    audio.setFocus(focus)

    elapsed = totalTime(now: now, including: active)
    let hint: Double? = now < hintUntil ? active.angle : nil
    if hint != hintAngle { hintAngle = hint }
    let newStatus = focus > 0.15 ? "Hold steady…" : "Creature \(index + 1) of \(Self.creaturesPerHunt). Listen…"
    if newStatus != status { status = newStatus }

    current = active
    let locking = hudLocking ? focus > 0 : focus > 0.25
    if locking != hudLocking {
      hudLocking = locking
      publishHUD()
    }
    if focus >= 1 { capture(active, now: now) }
  }

  private func spawn(now: CFTimeInterval) {
    let difficulty = Difficulty.ladder[min(index, Difficulty.ladder.count - 1)]
    let creature = hunt[index]
    // Never starts in front of you.
    let angle = Deg.wrap(yaw + .random(in: 70...290))
    current = Active(
      creature: creature,
      difficulty: difficulty,
      angle: angle,
      drift: difficulty.drift * (Bool.random() ? 1 : -1),
      flipAt: now + .random(in: 3...6),
      nextCall: now + 0.4,
      startedAt: now
    )
    tolerance = catchAngle(for: difficulty)
    focus = 0
    hudLocking = false
    status = "Creature \(index + 1) of \(Self.creaturesPerHunt). Listen…"
    publishHUD()
  }

  private func capture(_ active: Active, now: CFTimeInterval) {
    phase = .caught
    audio.setFocus(0)
    audio.silenceCreature()
    audio.playJingle()
    let caught = Catch(creature: active.creature, angle: active.angle, seconds: now - active.startedAt)
    catches.append(caught)
    lastCatch = caught
    current = nil
    focus = 0
    hintAngle = nil
    index += 1
    status = "You caught \(active.creature.name)."
    publishHUD()

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.8))
      guard self.phase == .caught else { return }
      self.lastCatch = nil
      if self.index >= Self.creaturesPerHunt {
        self.finish()
      } else {
        self.phase = .playing
        self.spawn(now: CACurrentMediaTime())
      }
    }
  }

  private func finish() {
    phase = .done
    let total = catches.reduce(0) { $0 + $1.seconds } + penalty
    elapsed = total
    if best == nil || total < (best ?? .infinity) {
      best = total
      isNewBest = true
      UserDefaults.standard.set(total, forKey: Self.bestKey)
    }
    status = "Hunt complete."
    publishHUD()
  }

  /// Mirrors the game state onto Meta Ray-Ban Display glasses, if any are connected.
  private func publishHUD() {
    let screen: HUDScreen
    switch phase {
    case .intro:
      screen = .intro(best: best)
    case .playing:
      screen = .hunting(number: index + 1, total: Self.creaturesPerHunt, locking: hudLocking)
    case .caught:
      guard let caught = lastCatch else { return }
      screen = .caught(name: caught.creature.name, imageName: caught.creature.imageName, seconds: caught.seconds)
    case .done:
      screen = .done(total: elapsed, penalty: penalty, isNewBest: isNewBest, best: best)
    }
    glasses.showOnGlasses(screen)
  }

  private func catchAngle(for difficulty: Difficulty) -> Double {
    wideCatch ? difficulty.tolerance * 1.6 : difficulty.tolerance
  }

  private func totalTime(now: CFTimeInterval, including active: Active) -> Double {
    catches.reduce(0) { $0 + $1.seconds } + penalty + (now - active.startedAt)
  }
}

/// CADisplayLink needs an Objective-C target.
private final class DisplayLinkTarget: NSObject {
  private let handler: (CFTimeInterval) -> Void
  init(_ handler: @escaping (CFTimeInterval) -> Void) { self.handler = handler }
  @objc func step(_ link: CADisplayLink) { handler(link.timestamp) }
}
