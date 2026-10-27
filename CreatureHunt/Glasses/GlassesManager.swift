import Foundation
import MWDATCore
import MWDATDisplay
import MWDATMotion

#if DEBUG
  import MWDATMockDevice
#endif

/// Everything that talks to Meta's glasses:
/// - registration with the Meta AI app,
/// - a device session with the Motion capability for head tracking,
/// - on Meta Ray-Ban Display glasses, the Display capability for in-lens screens,
/// - “Hey Meta, start Creature Hunt” voice launches.
///
/// Audio needs no SDK: the glasses are a Bluetooth audio device, so the game's sound plays
/// through their open-ear speakers like any other app's.
@MainActor
final class GlassesManager: ObservableObject {
  @Published private(set) var isRegistered = false
  @Published private(set) var registrationText = "Not connected to Meta AI yet."
  @Published private(set) var deviceName: String?
  @Published private(set) var isDeviceConnected = false
  @Published private(set) var isTracking = false
  @Published private(set) var trackingMessage: String?
  /// True while the connected glasses have a display the game is using.
  @Published private(set) var hasDisplay = false
  #if DEBUG
    /// The simulated Display glasses' screen, shown in the app for testing.
    @Published private(set) var mockDisplay: (any MockDisplayKit)?
  #endif
  /// Remembered between launches, so the wearer only has to fix it once.
  @Published var invertTurn = UserDefaults.standard.bool(forKey: "creatureHunt.invertTurn") {
    didSet {
      integrator.invert = invertTurn
      UserDefaults.standard.set(invertTurn, forKey: "creatureHunt.invertTurn")
    }
  }

  /// Head heading in degrees, clockwise-positive. Read every frame by the game.
  private(set) var yaw: Double = 0

  private var integrator = YawIntegrator()
  private var session: DeviceSession?
  private var motion: Motion?
  private var motionTask: Task<Void, Never>?
  private var sessionTask: Task<Void, Never>?
  private var observeTasks: [Task<Void, Never>] = []
  private var deviceTokens: [any AnyListenerToken] = []
  private let motionTokens = ListenerTokenBag()
  private let voiceTokens = ListenerTokenBag()
  private var voiceStream: VoiceInvocationsStream?
  private var voiceDevice: DeviceIdentifier?
  private var onVoiceLaunch: (@MainActor () -> Void)?
  private var wantsTracking = false

  /// Called when the wearer presses a button on the glasses' display.
  var onHUDAction: (@MainActor (HUDAction) -> Void)?
  private var display: Display?
  private var displayReady = false
  private var hudScreen: HUDScreen?
  private var sentScreen: HUDScreen?
  private var displayStateToken: (any AnyListenerToken)?

  init() {
    integrator.invert = invertTurn
  }

  // MARK: - Observing registration and devices

  func startObserving(onVoiceLaunch: @escaping @MainActor () -> Void) {
    self.onVoiceLaunch = onVoiceLaunch
    guard observeTasks.isEmpty else { return }

    if case .registered = Wearables.shared.registrationState { setRegistered(true) }

    observeTasks.append(
      Task { [weak self] in
        for await state in Wearables.shared.registrationStateStream() {
          guard let self else { return }
          switch state {
          case .registered:
            self.setRegistered(true)
          case .registering:
            self.registrationText = "Waiting for the Meta AI app…"
          case .unavailable:
            self.setRegistered(false)
            self.registrationText = "Meta AI isn’t available. Install it and turn on Developer Mode."
          default:
            self.setRegistered(false)
          }
        }
      })

    observeTasks.append(
      Task { [weak self] in
        for await identifiers in Wearables.shared.devicesStream() {
          guard let self else { return }
          self.watch(identifiers)
        }
      })
  }

  /// Opens the Meta AI app so the wearer can approve Creature Hunt.
  func connect() async {
    do {
      try await Wearables.shared.startRegistration()
    } catch {
      registrationText = "Couldn’t open Meta AI: \(error.localizedDescription)"
    }
  }

  private func setRegistered(_ registered: Bool) {
    isRegistered = registered
    registrationText = registered ? "Connected to Meta AI." : "Not connected to Meta AI yet."
    if registered { startVoiceIfPossible() }
  }

  private func watch(_ identifiers: [DeviceIdentifier]) {
    // Dropping the old tokens cancels their listeners.
    deviceTokens.removeAll()
    let devices = identifiers.compactMap { Wearables.shared.deviceForIdentifier($0) }
    publishDevices()
    for device in devices {
      deviceTokens.append(
        device.addLinkStateListener { [weak self] _ in
          Task { @MainActor in self?.publishDevices() }
        })
    }
  }

  private func publishDevices() {
    let devices = Wearables.shared.devices.compactMap { Wearables.shared.deviceForIdentifier($0) }
    let best = devices.first { $0.linkState == .connected } ?? devices.first
    deviceName = best.map { $0.name.isEmpty ? "Meta glasses" : $0.name }
    isDeviceConnected = best?.linkState == .connected
    if isRegistered { startVoiceIfPossible() }
    // Glasses came back while the player wants head tracking: pick it up again.
    if wantsTracking, isDeviceConnected, session == nil { startTracking() }
  }

  /// The pair on the wearer's face first, then any connected pair.
  private func preferredDevice() -> DeviceIdentifier? {
    let devices = Wearables.shared.devices.compactMap { Wearables.shared.deviceForIdentifier($0) }
    let worn = devices.first { $0.linkState == .connected && $0.donState == .donned }
    let connected = devices.first { $0.linkState == .connected }
    return (worn ?? connected)?.identifier
  }

  // MARK: - Head tracking

  func startTracking() {
    wantsTracking = true
    guard session == nil else { return }
    guard isRegistered else {
      trackingMessage = "Connect to Meta AI first."
      return
    }
    guard let identifier = preferredDevice() else {
      trackingMessage = "Turn on your glasses and put them on."
      return
    }
    do {
      let newSession = try Wearables.shared.createSession(
        deviceSelector: SpecificDeviceSelector(device: identifier))
      session = newSession
      // Subscribe before starting so the first transition isn't missed.
      let states = newSession.stateStream()
      sessionTask = Task { [weak self] in
        for await state in states {
          guard let self else { return }
          switch state {
          case .started:
            self.attachMotion(to: newSession)
            self.attachDisplayIfSupported(to: newSession, device: identifier)
          case .stopped:
            self.teardown(message: "Glasses disconnected. Head tracking stopped.")
            return
          default:
            break
          }
        }
      }
      try newSession.start()
      trackingMessage = "Connecting to your glasses…"
    } catch {
      session = nil
      trackingMessage = "Couldn’t start a glasses session: \(error.localizedDescription)"
    }
  }

  func stopTracking() {
    wantsTracking = false
    teardown(message: nil)
  }

  private func attachMotion(to session: DeviceSession) {
    guard motion == nil else { return }
    do {
      guard
        let attached = try session.addMotion(
          configuration: MotionConfiguration(samplingRate: .hz30))
      else {
        trackingMessage = "These glasses don’t report motion."
        return
      }
      motion = attached
      integrator.resetClock()

      // The sample stream can only be read once, so one task drains it.
      let samples = attached.samples
      motionTask = Task.detached { [weak self] in
        for await sample in samples {
          guard sample.source == .glasses else { continue }
          let accel = sample.accelerometer.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
          let gyro = sample.gyroscope.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
          let time = sample.timestampNs
          await self?.ingest(accel: accel, gyro: gyro, timestampNs: time)
        }
      }

      attached.statePublisher.listen { [weak self] state in
        // Other activity on the link (e.g. a photo) can stop motion; bring it back.
        if case .stopped = state {
          Task { @MainActor in self?.reviveMotion() }
        }
      }.store(in: motionTokens)
      attached.errorPublisher.listen { error in
        print("Creature Hunt motion error: \(error)")
      }.store(in: motionTokens)

      attached.start()  // Motion is returned stopped; nothing arrives until this.
      isTracking = true
      trackingMessage = nil
    } catch {
      trackingMessage =
        "Head tracking wouldn’t start: \(error.localizedDescription). Check that Motion is enabled for this app in Wearables Developer Center."
    }
  }

  private func ingest(accel: SIMD3<Double>?, gyro: SIMD3<Double>?, timestampNs: Int64) {
    integrator.ingest(accel: accel, gyro: gyro, timestampNs: timestampNs)
    yaw = integrator.yawDegrees
  }

  private func reviveMotion() {
    guard isTracking, let motion, motion.state == .stopped else { return }
    motion.start()
  }

  private func teardown(message: String?) {
    // Display stops before the session it belongs to.
    display?.stop()
    display = nil
    displayReady = false
    hasDisplay = false
    sentScreen = nil
    displayStateToken = nil
    motionTask?.cancel()
    motionTask = nil
    motion?.stop()
    try? session?.removeMotion()
    motion = nil
    sessionTask?.cancel()
    sessionTask = nil
    session?.stop()
    session = nil
    isTracking = false
    trackingMessage = message
    let tokens = motionTokens
    Task { await tokens.cancelAll() }
  }

  // MARK: - Display glasses

  /// Updates what the glasses' display shows. Safe to call on any glasses: without a display
  /// it just remembers the latest screen in case one connects.
  func showOnGlasses(_ screen: HUDScreen) {
    hudScreen = screen
    sendHUD()
  }

  private func attachDisplayIfSupported(to session: DeviceSession, device identifier: DeviceIdentifier) {
    guard display == nil,
      Wearables.shared.deviceForIdentifier(identifier)?.supportsDisplay() == true
    else { return }
    do {
      let capability = try session.addDisplay()
      display = capability
      hasDisplay = true
      displayStateToken = capability.statePublisher.listen { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          if state == .started {
            self.displayReady = true
            self.sentScreen = nil
            self.sendHUD()  // Show whatever the game is on right now.
          } else {
            self.displayReady = false
          }
        }
      }
      capability.start()
    } catch {
      print("Creature Hunt: the display wouldn’t attach: \(error)")
    }
  }

  private func sendHUD() {
    guard displayReady, let display, let screen = hudScreen, screen != sentScreen else { return }
    sentScreen = screen
    let view = GlassesHUD.view(for: screen) { [weak self] action in
      Task { @MainActor in self?.onHUDAction?(action) }
    }
    Task { @MainActor in
      do {
        try await display.send(view)
      } catch {
        print("Creature Hunt: couldn’t update the display: \(error)")
        if self.sentScreen == screen { self.sentScreen = nil }
      }
    }
  }

  // MARK: - Voice launch

  private func startVoiceIfPossible() {
    guard let identifier = preferredDevice(), identifier != voiceDevice else { return }
    do {
      let stream: VoiceInvocationsStream
      if let existing = voiceStream {
        stream = existing
        if voiceDevice != nil { stream.stop() }
      } else {
        stream = try VoiceInvocationsStream(wearables: Wearables.shared)
        voiceStream = stream
        stream.invocationsPublisher.listen { [weak self] invocation in
          guard let launch = invocation as? LaunchApp else { return }
          Task { @MainActor in
            // Meta AI waits for this answer, so answer first, then start the hunt.
            _ = await launch.responseHandle.sendSuccess(actionOutput: nil)
            self?.onVoiceLaunch?()
          }
        }.store(in: voiceTokens)
        stream.errorPublisher.listen { error in
          print("Creature Hunt voice launch error: \(error)")
        }.store(in: voiceTokens)
      }
      try stream.start(deviceIdentifier: identifier)
      voiceDevice = identifier
    } catch {
      voiceDevice = nil
      print("Creature Hunt voice launch unavailable: \(error)")
    }
  }

  // MARK: - Simulated glasses (debug builds only)

  #if DEBUG
    /// Pairs simulated glasses whose head slowly turns right, so the whole flow can be tried
    /// in the Simulator without hardware. With `withDisplay`, they're Meta Ray-Ban Display
    /// glasses and their screen is previewed inside the app.
    func useSimulatedGlasses(withDisplay: Bool = false) {
      MockDeviceKit.shared.enable()
      do {
        let glasses = try MockDeviceKit.shared.pairGlasses(
          model: withDisplay ? .metaRayBanDisplay : .rayBanMeta)
        glasses.powerOn()
        glasses.unfold()
        glasses.don()
        MockMotionFeed.install(on: glasses)
        mockDisplay = withDisplay ? glasses.services.display : nil
        trackingMessage =
          withDisplay
          ? "Simulated Display glasses paired. Their screen appears below."
          : "Simulated glasses paired. Their head turns slowly to the right."
      } catch {
        trackingMessage = "Couldn’t pair simulated glasses: \(error)"
      }
    }
  #endif
}
