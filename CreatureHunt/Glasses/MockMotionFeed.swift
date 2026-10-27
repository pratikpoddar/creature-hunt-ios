#if DEBUG
  import MWDATMockDevice

  /// A recorded-style motion feed for simulated glasses: the head is level and turns slowly to
  /// the right. Kept in its own file because MWDATMockDevice and MWDATMotion both define
  /// `MotionSample`.
  enum MockMotionFeed {
    static func install(on glasses: any MockGlasses) {
      let hertz = 30
      let seconds = 20
      let gravity: Float = 9.81
      // rad/s about the up axis. Negative = clockwise from above = turning right.
      let turnRate: Float = -0.35
      let intervalNs = Int64(1_000_000_000 / hertz)
      let samples = (0..<(hertz * seconds)).map { index in
        MotionSample(
          timestampNs: Int64(index) * intervalNs,
          // Same convention as Meta's BirdSpotter sample: a level head has up along +X.
          accelerometer: .init(x: gravity, y: 0, z: 0),
          gyroscope: .init(x: turnRate, y: 0, z: 0),
          source: .glasses
        )
      }
      glasses.services.motion.setMotionFeed(samples)
    }
  }
#endif
