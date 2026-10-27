import simd

/// Turns raw accelerometer + gyroscope samples into "which way am I facing".
///
/// It works in the sensor's own frame, so it doesn't depend on how the glasses (or phone)
/// define their axes: the accelerometer says where *up* is, and the gyroscope's spin around
/// that up axis is how fast the head is turning. Integrating that gives a heading relative to
/// where tracking started. It drifts slowly, which doesn't matter for a game that only cares
/// about turning *relative* to sounds.
struct YawIntegrator {
  /// Flip if turning right moves the lantern left on a particular device.
  var invert = false

  /// Degrees, clockwise-positive, in -180..<180.
  private(set) var yawDegrees: Double = 0

  private var up: SIMD3<Double>?
  private var lastTimestampNs: Int64?

  init(invert: Bool = false) {
    self.invert = invert
  }

  /// - Parameters:
  ///   - accel: Proper acceleration (gravity included), any unit. Points *up* when still.
  ///   - gyro: Angular velocity in rad/s, same frame as `accel`.
  ///   - timestampNs: Monotonic sample time in nanoseconds.
  mutating func ingest(accel: SIMD3<Double>?, gyro: SIMD3<Double>?, timestampNs: Int64) {
    if let accel, simd_length(accel) > 1 {
      let sample = simd_normalize(accel)
      // Low-pass so head acceleration doesn't wobble our idea of "up".
      up = up.map { simd_normalize($0 * 0.92 + sample * 0.08) } ?? sample
    }
    defer { lastTimestampNs = timestampNs }
    guard let gyro, let up, let last = lastTimestampNs else { return }
    let dt = Double(timestampNs - last) / 1_000_000_000
    guard dt > 0, dt < 0.5 else { return }

    // Right-hand rule: positive spin around "up" is counter-clockwise seen from above,
    // i.e. turning left. Our angles are clockwise-positive, hence the minus.
    let counterClockwise = simd_dot(gyro, up)
    let degrees = counterClockwise * dt * 180 / .pi
    yawDegrees = Deg.wrap(yawDegrees + (invert ? degrees : -degrees))
  }

  /// Forget timing and gravity (e.g. a new sensor session) but keep the current heading,
  /// so the game doesn't jump.
  mutating func resetClock() {
    lastTimestampNs = nil
    up = nil
  }
}
