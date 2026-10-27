import CoreMotion

/// Heading from the phone's own motion sensors: hold the phone in front of you and turn your
/// whole body. Uses the same integrator as the glasses, so both feel the same.
final class PhoneHeading {
  private let manager = CMMotionManager()
  private var integrator = YawIntegrator()

  /// Degrees, clockwise-positive.
  private(set) var yaw: Double = 0

  var isAvailable: Bool { manager.isDeviceMotionAvailable }

  func start() {
    guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
    integrator.resetClock()
    manager.deviceMotionUpdateInterval = 1.0 / 60
    manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
      guard let self, let motion else { return }
      // CoreMotion's gravity points down; the integrator wants up.
      let up = SIMD3(-motion.gravity.x, -motion.gravity.y, -motion.gravity.z) * 9.81
      let spin = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
      self.integrator.ingest(accel: up, gyro: spin, timestampNs: Int64(motion.timestamp * 1_000_000_000))
      self.yaw = self.integrator.yawDegrees
    }
  }

  func stop() {
    manager.stopDeviceMotionUpdates()
  }
}
